import AppKit
import ApplicationServices
import CryptoKit
import Darwin

private enum RecoveryTrace {
    static let enabled = ProcessInfo.processInfo.environment["RECTANGLE_FROST_TRACE_PATH"] != nil
    static func event(_ name: String, fields: @autoclosure () -> [String: Any] = [:]) {
        guard enabled else { return }
        WindowFrostDiagnostics.event("recovery." + name, fields: fields())
    }
}

// The recovery process owns every AX write between arm and disarm. The ordinary
// mover consults isWindowReserved before writing, including after an app restart.
enum WindowRecoveryError: Error, LocalizedError {
    case invalidRequest, identityChanged, windowUnavailable, reserved, transportClosed
    case journal(String), pending(String), rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Invalid window recovery request."
        case .identityChanged: return "The registered window process changed."
        case .windowUnavailable: return "The exact registered window is unavailable."
        case .reserved: return "This window already has a pending recovery transaction."
        case .transportClosed: return "The recovery connection closed."
        case .journal(let text), .pending(let text), .rejected(let text): return text
        }
    }
}

struct WindowRecoveryProcessIdentity: Codable, Equatable {
    let pid: Int32
    let uid: UInt32
    let startSec: UInt64
    let startUsec: UInt64
    let executable: String

    static func read(_ pid: Int32) -> WindowRecoveryProcessIdentity? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return WindowRecoveryProcessIdentity(pid: pid, uid: info.pbi_uid,
                                             startSec: info.pbi_start_tvsec, startUsec: info.pbi_start_tvusec,
                                             executable: String(cString: path))
    }

    var isSuspended: Bool {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return true }
        return info.pbi_status == SSTOP || info.pbi_status == SZOMB
    }
    enum Status { case same, gone, changed, unavailable }
    func status(reader: (Int32) -> WindowRecoveryProcessIdentity? = WindowRecoveryProcessIdentity.read,
                definitelyGone: (Int32) -> Bool = { Darwin.kill($0, 0) != 0 && errno == ESRCH }) -> Status {
        if let current = reader(pid) { return current == self ? .same : .changed }
        return definitelyGone(pid) ? .gone : .unavailable
    }
}

struct WindowRecoveryCommandGate {
    let generation: UUID
    private(set) var lastSequence: UInt64 = 0
    private(set) var recovering = false
    mutating func beginRecovery() { recovering = true }
    mutating func accept(generation: UUID, sequence: UInt64, isRecovery: Bool = false) -> Bool {
        guard generation == self.generation, sequence > lastSequence, !recovering || isRecovery else { return false }
        lastSequence = sequence
        return true
    }
}

/// A timeout does not exhaust recovery. Only a verified terminal observation does.
struct WindowRecoveryRetryPolicy {
    private(set) var attempts = 0
    private(set) var nextProbe: TimeInterval = 0
    private(set) var isPending = true
    mutating func failed(at now: TimeInterval) {
        attempts += 1
        nextProbe = now + min(2, 0.25 * pow(2, Double(min(attempts - 1, 3))))
    }
    mutating func responsive(at now: TimeInterval) { nextProbe = now }
    mutating func completed() { isPending = false }
    func shouldProbe(at now: TimeInterval) -> Bool { isPending && now >= nextProbe }
}

/// A separate main-loop heartbeat distinguishes a live PID from a live helper.
/// Require a second stale observation so sleep/wake scheduling cannot trigger an
/// immediate replacement before the helper's run loop has had a chance to run.
struct WindowRecoveryHelperHealthPolicy {
    private var firstObservedAt: TimeInterval?
    private var staleObservedAt: TimeInterval?
    mutating func shouldReclaim(at now: TimeInterval, heartbeatUptime: TimeInterval?) -> Bool {
        if firstObservedAt == nil { firstObservedAt = now }
        let heartbeat = heartbeatUptime.flatMap { $0.isFinite && $0 <= now + 1 ? $0 : nil }
        let lastProgress = heartbeat ?? firstObservedAt ?? now
        guard now-lastProgress > 3 else { staleObservedAt = nil; return false }
        guard let observed = staleObservedAt else { staleObservedAt = now; return false }
        return now-observed >= 1
    }
}

/// A replacement can be alive before it has rewritten the old owner's state.
/// Keep monitoring its durable launch identity once the previous owner is
/// confirmed gone; an unreadable previous identity never authorizes takeover.
enum WindowRecoveryHelperSelection {
    static func select(journal: WindowRecoveryProcessIdentity?, launch: WindowRecoveryProcessIdentity?,
                       status: (WindowRecoveryProcessIdentity) -> WindowRecoveryProcessIdentity.Status = { $0.status() }) -> WindowRecoveryProcessIdentity? {
        if let journal = journal {
            switch status(journal) {
            case .same: return journal
            case .unavailable: return nil
            case .gone, .changed: break
            }
        }
        guard let launch = launch, status(launch) == .same else { return nil }
        return launch
    }
}

struct WindowRecoveryPrewarmRetryPolicy {
    private(set) var attempts = 0
    var isExhausted: Bool { attempts >= 3 }
    mutating func nextDelay() -> TimeInterval? {
        guard !isExhausted else { return nil }
        let delay = pow(2, Double(attempts)); attempts += 1; return delay
    }
    mutating func reset() { attempts = 0 }
}

struct WindowRecoveryStandbyOwnership {
    enum Phase { case starting, ready, claimed, discarded }
    let parent: WindowRecoveryProcessIdentity
    let helper: WindowRecoveryProcessIdentity
    private(set) var phase: Phase = .starting
    mutating func acceptReady(parent: WindowRecoveryProcessIdentity, helper: WindowRecoveryProcessIdentity) -> Bool {
        guard phase == .starting || phase == .ready, parent == self.parent, helper == self.helper else { return false }
        phase = .ready; return true
    }
    mutating func claim(parent: WindowRecoveryProcessIdentity?, helper: WindowRecoveryProcessIdentity?) -> Bool {
        guard phase == .ready, parent == self.parent, helper == self.helper else { return false }
        phase = .claimed; return true
    }
    mutating func discard() -> Bool {
        guard phase == .starting || phase == .ready else { return false }
        phase = .discarded; return true
    }
}

private struct RecoveryStandbyCommand: Codable {
    let kind: String
    let parent: WindowRecoveryProcessIdentity
    var requestPath: String?
}

private struct RecoveryHelperLaunch: Codable {
    let generation: UUID
    let requestSHA: String
    let helper: WindowRecoveryProcessIdentity
    let uptime: TimeInterval
}

private struct RecoveryHelperHeartbeat: Codable {
    let generation: UUID
    let requestSHA: String
    let helper: WindowRecoveryProcessIdentity
    let sequence: UInt64
    let uptime: TimeInterval
}

struct RecoveryRequest: Codable {
    let schema: Int
    let generation: UUID
    let bootSession: String
    let parent: WindowRecoveryProcessIdentity
    let target: WindowRecoveryProcessIdentity
    let windowID: CGWindowID
    let source: CGRect
    let destination: CGRect
    let createdAt: TimeInterval
    let releasedSnap: Bool?
    // Native movement has already changed source when ownership is acquired.
    // Keep admission/cover geometry separate from the pre-drag recovery target.
    let recoverySource: CGRect?

    var restorationFrame: CGRect { recoverySource ?? source }
}

private struct RecoveryJournalState: Codable {
    let generation: UUID
    let requestSHA: String
    var helper: WindowRecoveryProcessIdentity?
    var phase: String
    var possiblyMoved: Bool
    var lastFrame: CGRect?
    var reason: String?
    var sequence: UInt64
    var attempts: Int
    var uptime: TimeInterval
    var wallTime: TimeInterval
    var terminal: Bool { ["disarmed", "recovered", "targetGone", "cancelled"].contains(phase) }
}

private struct RecoveryMessage: Codable {
    let generation: UUID
    let sequence: UInt64
    let kind: String
    var operation: WindowParkingOperation?
    var frame: CGRect?
    var timeout: TimeInterval?
    var reason: String?
    var requestSHA: String?
    var helper: WindowRecoveryProcessIdentity?
    var parent: WindowRecoveryProcessIdentity?
    var uptime: TimeInterval?
}

struct WindowRecoveryPendingJournal {
    let generation: UUID
    let windowID: CGWindowID
    let pid: Int32
    let recoveryPending: Bool
    fileprivate let request: RecoveryRequest
    fileprivate let directory: URL
    fileprivate let state: RecoveryJournalState?
}

enum WindowRecoveryGeometry {
    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } && frame.width > 0 && frame.height > 0
    }
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        valid(a) && valid(b) && abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance && abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
    static func displaySnapshot() -> [WindowParkingDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDisplayIsActive(number.uint32Value) != 0 else { return nil }
            let bounds = CGDisplayBounds(number.uint32Value)
            let full = screen.frame, usable = screen.visibleFrame
            let mapped = CGRect(x: bounds.minX + usable.minX-full.minX,
                                y: bounds.minY + full.maxY-usable.maxY,
                                width: usable.width, height: usable.height).intersection(bounds)
            guard valid(mapped) else { return nil }
            return WindowParkingDisplay(id: number.uint32Value, bounds: bounds, visibleFrame: mapped)
        }
    }
    static func visible(_ frame: CGRect, displays: [WindowParkingDisplay]) -> Bool {
        visible(frame, displays: displays, minimumWidth: 80)
    }
    /// A released edge drag can leave only its grab point and a narrow titlebar
    /// strip onscreen. This admits the source only; recovery endpoints still use
    /// the ordinary reachable-width requirement. Parked one-point slivers fail.
    static func visibleReleasedSource(_ frame: CGRect, displays: [WindowParkingDisplay]) -> Bool {
        visible(frame, displays: displays, minimumWidth: 2)
            && !narrowCorner(frame, displays: displays)
    }
    private static func visible(_ frame: CGRect, displays: [WindowParkingDisplay], minimumWidth: CGFloat) -> Bool {
        guard valid(frame) else { return false }
        return displays.contains { display in
            let overlap = display.visibleFrame.intersection(frame)
            return !overlap.isNull && overlap.width >= min(minimumWidth, frame.width) && overlap.height >= min(30, frame.height)
                && frame.minY >= display.visibleFrame.minY-2 && frame.minY < display.visibleFrame.maxY-20
        }
    }
    static func narrowCorner(_ frame: CGRect, displays: [WindowParkingDisplay]) -> Bool {
        valid(frame) && !displays.isEmpty && displays.allSatisfy {
            let intersection = $0.bounds.intersection(frame)
            return intersection.isNull || intersection.isEmpty || intersection.width <= 1.1
        }
    }
    static func safeParkingObservation(_ frame: CGRect, departure: CGRect?,
                                       source: CGRect, displays: [WindowParkingDisplay],
                                       departureCover: CGRect? = nil) -> Bool {
        if narrowCorner(frame, displays: displays) { return true }
        // WindowServer may still show the last verified departure while a
        // parking write settles. A repeated command can retain a newer endpoint
        // cover; it does not replace the lease's original recovery source.
        let cover = departureCover ?? source
        guard departureCover == nil || visible(cover, displays: displays),
              let departure, valid(departure), cover.contains(departure),
              departure.origin == cover.origin else { return false }
        return near(frame, departure, tolerance: 1)
    }
    static func safe(_ source: CGRect, actualSize: CGSize? = nil, displays: [WindowParkingDisplay]) -> CGRect? {
        var frame = source
        if let size = actualSize { frame.size = size }
        guard valid(frame), !displays.isEmpty else { return nil }
        // Preserve a user's partly offscreen placement when its titlebar is
        // still reachable. Disconnected or unreachable sources are clamped below.
        if visible(frame, displays: displays) { return frame }
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        guard let display = displays.max(by: { area($0.visibleFrame.intersection(source)) < area($1.visibleFrame.intersection(source)) }) else { return nil }
        let usable = display.visibleFrame
        frame.origin.x = frame.width > usable.width ? usable.minX : min(max(frame.minX, usable.minX), usable.maxX-frame.width)
        frame.origin.y = frame.height > usable.height ? usable.minY : min(max(frame.minY, usable.minY), usable.maxY-frame.height)
        return frame
    }
}

/// Restore the source display before asking the app to restore its source size.
/// A size accepted on a parking display is not evidence of an app size limit.
enum WindowRecoveryRestoration {
    static func perform(source: CGRect, displays: () -> [WindowParkingDisplay],
                        read: () throws -> CGRect,
                        write: (WindowParkingOperation.Attribute, CGRect) throws -> Void,
                        verify: (CGRect) throws -> CGRect) throws -> CGRect {
        let current = try read()
        guard let positioned = WindowRecoveryGeometry.safe(source, actualSize: current.size, displays: displays()) else {
            throw WindowRecoveryError.invalidRequest
        }
        try write(.position, positioned)
        // The AX and CG readback must settle on the source display before size
        // restoration; otherwise cross-display height clamping can persist.
        _ = try verify(positioned)
        try write(.size, source)
        guard let desired = WindowRecoveryGeometry.safe(source, displays: displays()) else {
            throw WindowRecoveryError.invalidRequest
        }
        do { return try verify(desired) }
        catch RecoveryAXFailure.mismatch {
            // Only after the bounded exact-size observation may an app's actual
            // minimum/maximum size be accepted. Reposition that accepted frame.
            let accepted = try read()
            guard let safe = WindowRecoveryGeometry.safe(source, actualSize: accepted.size, displays: displays()) else {
                throw WindowRecoveryError.invalidRequest
            }
            try write(.position, safe)
            return try verify(safe)
        }
    }
}

final class WindowRecoveryFileLock {
    private var descriptor: Int32 = -1
    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw WindowRecoveryError.journal("Cannot open recovery lock.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor); descriptor = -1
            throw WindowRecoveryError.reserved
        }
    }
    deinit { if descriptor >= 0 { flock(descriptor, LOCK_UN); Darwin.close(descriptor) } }
}

private enum RecoveryJournal {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    static var decoder: JSONDecoder { JSONDecoder() }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rectangle/WindowRecovery/v1", isDirectory: true)
    }
    static func bootSession() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
    static func secureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR,
              chmod(url.path, S_IRWXU) == 0 else { throw WindowRecoveryError.journal("Unsafe recovery directory.") }
    }
    static func prepareRoot() throws { try secureDirectory(root); try secureDirectory(root.appendingPathComponent("locks")) }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func write<T: Encodable>(_ value: T, to url: URL, durable: Bool = true) throws {
        let data = try encoder.encode(value)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw WindowRecoveryError.journal("Cannot create recovery journal.") }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count-offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw WindowRecoveryError.journal("Cannot write recovery journal.") }
                offset += count
            }
        }
        guard (!durable || fsync(fd) == 0), rename(temporary.path, url.path) == 0 else { throw WindowRecoveryError.journal("Cannot commit recovery journal.") }
        let directory = durable ? Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC) : -1
        if directory >= 0 { defer { Darwin.close(directory) }; guard fsync(directory) == 0 else { throw WindowRecoveryError.journal("Cannot sync recovery directory.") } }
    }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw WindowRecoveryError.invalidRequest }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o077) == 0, info.st_size > 0, info.st_size <= 65_536 else { throw WindowRecoveryError.invalidRequest }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return try decoder.decode(type, from: handle.readDataToEndOfFile())
    }
    static func requestSHA(at directory: URL) throws -> String {
        let request: RecoveryRequest = try read(RecoveryRequest.self, from: directory.appendingPathComponent("request.json"))
        return hash(try encoder.encode(request))
    }
    static func lockURL(_ request: RecoveryRequest) -> URL {
        let key = "\(request.bootSession)-\(request.target.pid)-\(request.target.startSec)-\(request.target.startUsec)-\(request.windowID)"
        return root.appendingPathComponent("locks/\(hash(Data(key.utf8))).lock")
    }
    static func remove(_ directory: URL) { try? FileManager.default.removeItem(at: directory) }
    static func scan() -> [WindowRecoveryPendingJournal] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { directory in
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  let request = try? read(RecoveryRequest.self, from: directory.appendingPathComponent("request.json")),
                  request.schema == 1, request.generation.uuidString == directory.lastPathComponent else { return nil }
            let state = try? read(RecoveryJournalState.self, from: directory.appendingPathComponent("state.json"))
            if state?.terminal == true { remove(directory); return nil }
            // A record from a previous boot cannot refer to a surviving target.
            if request.bootSession != bootSession() { remove(directory); return nil }
            return WindowRecoveryPendingJournal(generation: request.generation, windowID: request.windowID, pid: request.target.pid,
                                                recoveryPending: state?.phase == "recovering", request: request, directory: directory, state: state)
        }
    }
}

/// EOF stays readable. Detach on the I/O callback itself, before enqueueing any
/// main-thread work, or a dead parent can flood the helper's run loop forever.
enum WindowRecoveryInput {
    static func readAvailable(from handle: FileHandle) -> Data {
        let data = handle.availableData
        if data.isEmpty { handle.readabilityHandler = nil }
        return data
    }
}

private final class RecoveryLineReader {
    private var data = Data()
    func takeBufferedData() -> Data { let buffered = data; data.removeAll(); return buffered }
    func consume(_ chunk: Data) throws -> [RecoveryMessage] {
        data.append(chunk)
        guard data.count <= 131_072 else { throw WindowRecoveryError.invalidRequest }
        var messages: [RecoveryMessage] = []
        while let newline = data.firstIndex(of: 10) {
            let line = data[..<newline]
            guard line.count <= 65_536 else { throw WindowRecoveryError.invalidRequest }
            messages.append(try RecoveryJournal.decoder.decode(RecoveryMessage.self, from: line))
            data.removeSubrange(...newline)
        }
        return messages
    }
}

private func recoveryWrite<T: Encodable>(_ message: T, to descriptor: Int32) -> Bool {
    guard var data = try? RecoveryJournal.encoder.encode(message), data.count <= 65_536 else { return false }
    data.append(10)
    _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
    return data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return false }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count-offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
}

/// Parent-owned idle process. Once claimed, this object can no longer terminate
/// the process: its pipes and lifetime belong exclusively to the transaction.
private final class RecoveryStandbyProcess {
    let process: Process
    let input: Pipe
    let output: Pipe
    private(set) var ownership: WindowRecoveryStandbyOwnership
    private let reader = RecoveryLineReader()
    private let writer = DispatchQueue(label: "Rectangle.WindowRecovery.standby-send")
    private var timer: Timer?
    private var lastReply = ProcessInfo.processInfo.systemUptime
    private let launchedAt = ProcessInfo.processInfo.systemUptime
    var forward: ((Data) -> Void)?

    init(executable: URL, parent: WindowRecoveryProcessIdentity) throws {
        process = Process(); input = Pipe(); output = Pipe()
        // Initialize before spawning; replace this placeholder immediately after
        // exec returns, before any asynchronous ready callback can be consumed.
        ownership = WindowRecoveryStandbyOwnership(parent: parent, helper: parent)
        process.executableURL = executable
        process.arguments = ["--rectangle-window-recovery-standby"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        guard let helper = WindowRecoveryProcessIdentity.read(process.processIdentifier), helper.uid == parent.uid,
              helper.executable == parent.executable, helper.pid != parent.pid else { throw WindowRecoveryError.identityChanged }
        ownership = WindowRecoveryStandbyOwnership(parent: parent, helper: helper)
        input.fileHandleForReading.closeFile(); output.fileHandleForWriting.closeFile()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = WindowRecoveryInput.readAvailable(from: handle)
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.discard(unexpected: true) } }
        let heartbeatTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer = heartbeatTimer
        RunLoop.main.add(heartbeatTimer, forMode: .common)
        RecoveryTrace.event("prewarmLaunched", fields: ["helperPID": helper.pid])
    }
    private func receive(_ data: Data) {
        if let forward = forward { forward(data); return }
        guard ownership.phase != .discarded else { return }
        guard !data.isEmpty else { discard(unexpected: true); return }
        do {
            for message in try reader.consume(data) {
                guard ["standby-ready", "standby-heartbeat"].contains(message.kind),
                      let parent = message.parent, let helper = message.helper,
                      ownership.acceptReady(parent: parent, helper: helper), helper.status() == .same else { discard(unexpected: true); return }
                let now = ProcessInfo.processInfo.systemUptime
                guard let timestamp = message.uptime, timestamp.isFinite, timestamp <= now + 1 else { discard(unexpected: true); return }
                lastReply = timestamp
                if message.kind == "standby-ready" {
                    WindowRecoverySession.standbyBecameReady(self)
                    RecoveryTrace.event("prewarmReady", fields: ["helperPID": helper.pid, "startupMilliseconds": (lastReply-launchedAt)*1000])
                }
            }
        } catch { discard(unexpected: true) }
    }
    private func tick() {
        guard ownership.phase == .starting || ownership.phase == .ready else { return }
        guard WindowAnimator.frostedEnabled, AXIsProcessTrusted() else { WindowRecoverySession.cancelPrewarm(); return }
        guard ownership.parent.status() == .same, process.isRunning,
              ProcessInfo.processInfo.systemUptime-lastReply <= 3 else { discard(unexpected: true); return }
        let command = RecoveryStandbyCommand(kind: "heartbeat", parent: ownership.parent)
        let handle = input.fileHandleForWriting
        writer.async { [weak self] in
            if !recoveryWrite(command, to: handle.fileDescriptor) { DispatchQueue.main.async { self?.discard(unexpected: true) } }
        }
    }
    func claim() -> Data? {
        guard ProcessInfo.processInfo.systemUptime-lastReply <= 1.5, process.isRunning, !ownership.helper.isSuspended,
              ownership.claim(parent: WindowRecoveryProcessIdentity.read(getpid()), helper: WindowRecoveryProcessIdentity.read(ownership.helper.pid)) else { return nil }
        timer?.invalidate(); timer = nil
        // Drain the small, bounded idle-heartbeat queue before prepare can enter
        // the pipe. No standby-format message may follow the handoff command.
        writer.sync { }
        RecoveryTrace.event("prewarmClaimed", fields: ["helperPID": ownership.helper.pid, "idleMilliseconds": (ProcessInfo.processInfo.systemUptime-launchedAt)*1000])
        return reader.takeBufferedData()
    }
    func discard(unexpected: Bool = false) {
        guard ownership.discard() else { return }
        timer?.invalidate(); timer = nil
        output.fileHandleForReading.readabilityHandler = nil
        let helper = ownership.helper, parent = ownership.parent
        // Closing stdin gives responsive idle helpers an immediate, write-free
        // exit. Signals are limited to this exact unclaimed child if it is stuck.
        let inputHandle = input.fileHandleForWriting
        writer.async { inputHandle.closeFile() }
        DispatchQueue.global(qos: .utility).async {
            guard helper.pid != parent.pid, helper.pid != getpid(), helper.uid == getuid(), helper.executable == parent.executable else { return }
            if helper.status() == .same { _ = Darwin.kill(helper.pid, SIGTERM) }
            for _ in 0..<6 { if helper.status() != .same { return }; Thread.sleep(forTimeInterval: 0.05) }
            if helper.status() == .same { _ = Darwin.kill(helper.pid, SIGKILL) }
        }
        RecoveryTrace.event("prewarmDiscarded", fields: ["helperPID": helper.pid])
        if unexpected { WindowRecoverySession.standbyDidDiscard(self) }
    }
}

final class WindowRecoverySession {
    private static var sessions: [UUID: WindowRecoverySession] = [:]
    private static var reservations: [UUID: CGWindowID] = [:]
    private static var loadedReservations = false
    private static var prewarmingEnabled = false
    private static var standby: RecoveryStandbyProcess?
    private static var prewarmRetryPolicy = WindowRecoveryPrewarmRetryPolicy()
    private static var prewarmRetryWork: DispatchWorkItem?

    static func prewarm() {
        precondition(Thread.isMainThread)
        prewarmRetryWork?.cancel(); prewarmRetryWork = nil
        prewarmRetryPolicy.reset()
        guard WindowAnimator.frostedEnabled, AXIsProcessTrusted() else { cancelPrewarm(); return }
        prewarmingEnabled = true
        ensurePrewarm()
    }
    private static func ensurePrewarm() {
        guard prewarmingEnabled, WindowAnimator.frostedEnabled, AXIsProcessTrusted(), sessions.isEmpty else { return }
        if let standby = standby, standby.ownership.phase == .starting || standby.ownership.phase == .ready { return }
        guard let executable = Bundle.main.executableURL, let parent = WindowRecoveryProcessIdentity.read(getpid()) else { return }
        do { standby = try RecoveryStandbyProcess(executable: executable, parent: parent) }
        catch { standby = nil; schedulePrewarmRetry() }
    }
    fileprivate static func standbyBecameReady(_ candidate: RecoveryStandbyProcess) {
        guard standby === candidate else { return }
        prewarmRetryPolicy.reset()
        prewarmRetryWork?.cancel(); prewarmRetryWork = nil
    }
    fileprivate static func standbyDidDiscard(_ candidate: RecoveryStandbyProcess) {
        guard standby === candidate else { return }
        standby = nil
        schedulePrewarmRetry()
    }
    private static func schedulePrewarmRetry() {
        guard prewarmingEnabled, WindowAnimator.frostedEnabled, AXIsProcessTrusted(), sessions.isEmpty,
              prewarmRetryWork == nil, let delay = prewarmRetryPolicy.nextDelay() else { return }
        let work = DispatchWorkItem {
            prewarmRetryWork = nil
            ensurePrewarm()
        }
        prewarmRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    static func cancelPrewarm() {
        precondition(Thread.isMainThread)
        prewarmingEnabled = false
        prewarmRetryWork?.cancel(); prewarmRetryWork = nil
        standby?.discard(); standby = nil
    }
    private static func takeStandby() -> (RecoveryStandbyProcess, Data)? {
        guard let candidate = standby else { return nil }
        guard let buffered = candidate.claim() else { candidate.discard(); standby = nil; return nil }
        standby = nil
        return (candidate, buffered)
    }
    private static var releaseActions: [CGWindowID: [() -> Void]] = [:]
    static func whenReleased(windowID: CGWindowID, action: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        if isWindowReserved(windowID) { releaseActions[windowID, default: []].append(action) }
        else { action() }
    }
    static var pendingWindowIDs: Set<CGWindowID> {
        if !loadedReservations { loadedReservations = true; for entry in readJournals() { reservations[entry.generation] = entry.windowID } }
        return Set(reservations.values)
    }
    static func isWindowReserved(_ id: CGWindowID) -> Bool { pendingWindowIDs.contains(id) }
    static func readJournals() -> [WindowRecoveryPendingJournal] { RecoveryJournal.scan() }
    static func resumePendingRecovery() {
        precondition(Thread.isMainThread)
        for journal in readJournals() where sessions[journal.generation] == nil {
            let session = WindowRecoverySession(request: journal.request, directory: journal.directory)
            session.recoveryPending = true
            sessions[journal.generation] = session; reservations[journal.generation] = journal.windowID
            session.observeOrResume()
        }
        loadedReservations = true
    }

    let targetWindowID: CGWindowID
    let pid: Int32
    private(set) var recoveryPending = false
    private let request: RecoveryRequest
    private let directory: URL
    private var process: Process?
    private var commandPipe: Pipe?
    private var responsePipe: Pipe?
    private var adoptedStandby: RecoveryStandbyProcess?
    private var reader = RecoveryLineReader()
    private let sendQueue = DispatchQueue(label: "Rectangle.WindowRecovery.transport")
    private var sequence: UInt64 = 0
    private var heartbeat: Timer?
    private var monitor: Timer?
    private var started: ((Result<WindowRecoverySession, Error>) -> Void)?
    private var operations: [UInt64: (Result<CGRect, Error>) -> Void] = [:]
    private var finishes: [UInt64: (Result<Void, Error>) -> Void] = [:]
    private var recoveries: [(Result<CGRect, Error>) -> Void] = []
    private var helperIdentity: WindowRecoveryProcessIdentity?
    private var isTerminal = false
    private var launchAttempt = 0
    private var nextLaunch: TimeInterval = 0
    private var helperHealth = WindowRecoveryHelperHealthPolicy()
    private var reclaimingHelper = false

    private init(request: RecoveryRequest, directory: URL) {
        self.request = request; self.directory = directory; targetWindowID = request.windowID; pid = request.target.pid
    }

    static func start(element: AccessibilityElement, source: CGRect, destination: CGRect,
                      releasedSnap: Bool = false, recoverySource: CGRect? = nil,
                      completion: @escaping (Result<WindowRecoverySession, Error>) -> Void) {
        precondition(Thread.isMainThread)
        // Admission never completes inline: callers must install the accepted
        // transition token before either rejection or successful arming arrives.
        let deliverAdmission: (Result<WindowRecoverySession, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        guard let id = element.windowId, id != 0, let pid = element.pid,
              WindowRecoveryGeometry.valid(source), WindowRecoveryGeometry.valid(destination),
              WindowRecoveryGeometry.valid(recoverySource ?? source),
              let target = WindowRecoveryProcessIdentity.read(pid), let parent = WindowRecoveryProcessIdentity.read(getpid()),
              target.uid == getuid(), !isWindowReserved(id) else {
            deliverAdmission(.failure(WindowRecoveryError.reserved)); return
        }
        let generation = UUID()
        let request = RecoveryRequest(schema: 1, generation: generation, bootSession: RecoveryJournal.bootSession(),
                                      parent: parent, target: target, windowID: id, source: source, destination: destination,
                                      createdAt: Date().timeIntervalSince1970, releasedSnap: releasedSnap,
                                      recoverySource: recoverySource)
        let directory = RecoveryJournal.root.appendingPathComponent(generation.uuidString, isDirectory: true)
        do {
            guard !request.bootSession.isEmpty else { throw WindowRecoveryError.invalidRequest }
            try RecoveryJournal.prepareRoot(); try RecoveryJournal.secureDirectory(directory)
            try RecoveryJournal.write(request, to: directory.appendingPathComponent("request.json"))
            let session = WindowRecoverySession(request: request, directory: directory)
            session.started = deliverAdmission
            sessions[generation] = session; reservations[generation] = id
            try session.launch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak session] in
                guard let session = session, let completion = session.started else { return }
                session.started = nil
                session.recover(reason: "Recovery admission timed out") { _ in }
                completion(.failure(WindowRecoveryError.pending("Recovery admission timed out.")))
            }
        } catch {
            reservations.removeValue(forKey: generation); sessions.removeValue(forKey: generation)
            RecoveryJournal.remove(directory); deliverAdmission(.failure(error))
        }
    }

    func perform(_ operation: WindowParkingOperation, timeout: TimeInterval,
                 completion: @escaping (Result<CGRect, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard !isTerminal, !recoveryPending, helperIdentity != nil else { completion(.failure(WindowRecoveryError.pending("Window recovery is pending."))); return }
        let value = min(2, max(0.05, timeout))
        let number = nextSequence()
        operations[number] = completion
        send(RecoveryMessage(generation: request.generation, sequence: number, kind: "perform", operation: operation, timeout: value))
        DispatchQueue.main.asyncAfter(deadline: .now() + value + 0.75) { [weak self] in
            guard let self = self, let completion = self.operations.removeValue(forKey: number) else { return }
            self.recover(reason: "Window operation timed out") { _ in }
            completion(.failure(WindowRecoveryError.pending("Window operation timed out; recovery remains active.")))
        }
    }

    func recover(reason: String, completion: @escaping (Result<CGRect, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard !isTerminal else { completion(.failure(WindowRecoveryError.transportClosed)); return }
        recoveryPending = true
        recoveries.append(completion)
        failNormalCommands(WindowRecoveryError.pending(reason))
        send(RecoveryMessage(generation: request.generation, sequence: nextSequence(), kind: "recover", reason: reason))
        // The UI can detach after a bounded wait. This does not release the lease.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.recoveryPending, !self.isTerminal else { return }
            let callbacks = self.recoveries; self.recoveries.removeAll()
            callbacks.forEach { $0(.failure(WindowRecoveryError.pending("The target is not responding; recovery will retry when it responds."))) }
        }
        startMonitor()
    }

    func finish(frame: CGRect, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard !isTerminal, !recoveryPending else { completion(.failure(WindowRecoveryError.pending("Window recovery is pending."))); return }
        let number = nextSequence(); finishes[number] = completion
        send(RecoveryMessage(generation: request.generation, sequence: number, kind: "finish", frame: frame))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let completion = self.finishes.removeValue(forKey: number) else { return }
            self.recover(reason: "Final placement verification timed out") { _ in }
            completion(.failure(WindowRecoveryError.pending("Final placement verification timed out.")))
        }
    }

    private func nextSequence() -> UInt64 { sequence += 1; return sequence }
    private func launch() throws {
        reader = RecoveryLineReader()
        helperHealth = WindowRecoveryHelperHealthPolicy()
        if let (standby, buffered) = Self.takeStandby() {
            adoptedStandby = standby
            standby.forward = { [weak self] data in self?.receive(data) }
            bind(process: standby.process, input: standby.input, output: standby.output)
            try registerLaunch(standby.ownership.helper)
            if !buffered.isEmpty { receive(buffered) }
            let command = RecoveryStandbyCommand(kind: "prepare", parent: standby.ownership.parent,
                                                  requestPath: directory.appendingPathComponent("request.json").path)
            let handle = standby.input.fileHandleForWriting
            sendQueue.async { [weak self] in
                if !recoveryWrite(command, to: handle.fileDescriptor) { DispatchQueue.main.async { self?.childExited() } }
            }
            startHeartbeat()
            return
        }
        guard let executable = Bundle.main.executableURL else { throw WindowRecoveryError.invalidRequest }
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = executable
        child.arguments = ["--rectangle-window-recovery", directory.appendingPathComponent("request.json").path]
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        bind(process: child, input: input, output: output)
        try child.run()
        input.fileHandleForReading.closeFile(); output.fileHandleForWriting.closeFile()
        guard let identity = WindowRecoveryProcessIdentity.read(child.processIdentifier) else { throw WindowRecoveryError.identityChanged }
        try registerLaunch(identity)
        startHeartbeat()
    }
    private func registerLaunch(_ helper: WindowRecoveryProcessIdentity) throws {
        let launch = RecoveryHelperLaunch(generation: request.generation, requestSHA: try RecoveryJournal.requestSHA(at: directory),
                                          helper: helper, uptime: ProcessInfo.processInfo.systemUptime)
        try RecoveryJournal.write(launch, to: directory.appendingPathComponent("launch.json"))
    }
    private func bind(process child: Process, input: Pipe, output: Pipe) {
        process = child; commandPipe = input; responsePipe = output
        output.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = WindowRecoveryInput.readAvailable(from: handle)
            DispatchQueue.main.async {
                guard let self = self, self.process === child else { return }
                self.receive(data)
            }
        }
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let self = self, self.process === child else { return }
                self.childExited()
            }
        }
    }
    private func startHeartbeat() {
        heartbeat?.invalidate()
        let heartbeatTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !self.isTerminal else { return }
            self.send(RecoveryMessage(generation: self.request.generation, sequence: self.nextSequence(), kind: "heartbeat"))
        }
        heartbeat = heartbeatTimer
        RunLoop.main.add(heartbeatTimer, forMode: .common)
        startMonitor()
    }
    private func send(_ message: RecoveryMessage) {
        guard let handle = commandPipe?.fileHandleForWriting else { return }
        sendQueue.async { [weak self] in
            if !recoveryWrite(message, to: handle.fileDescriptor) {
                DispatchQueue.main.async {
                    guard let self = self, self.commandPipe?.fileHandleForWriting === handle else { return }
                    self.childExited()
                }
            }
        }
    }
    private func receive(_ data: Data) {
        guard !isTerminal else { return }
        if data.isEmpty { childExited(); return }
        do { for message in try reader.consume(data) { handle(message) } }
        catch { recover(reason: "Invalid recovery response") { _ in } }
    }
    private func handle(_ message: RecoveryMessage) {
        guard message.generation == request.generation else { return }
        switch message.kind {
        case "armed":
            guard let helper = message.helper, helper.status() == .same,
                  message.requestSHA == (try? RecoveryJournal.requestSHA(at: directory)) else {
                recover(reason: "Recovery helper identity mismatch") { _ in }; return
            }
            helperIdentity = helper
            let callback = started; started = nil
            if recoveryPending { send(RecoveryMessage(generation: request.generation, sequence: nextSequence(), kind: "recover", reason: "Admission already cancelled")) }
            else { callback?(.success(self)) }
        case "performed":
            if let frame = message.frame, !recoveryPending { operations.removeValue(forKey: message.sequence)?(.success(frame)) }
        case "recovering":
            recoveryPending = true; failNormalCommands(WindowRecoveryError.pending(message.reason ?? "Window recovery is pending."))
        case "recovered", "disarmed", "targetGone", "cancelled":
            let frame = message.frame ?? request.source
            terminateSession(outcome: message.kind == "targetGone" ? .failure(WindowRecoveryError.identityChanged) : .success(frame), disarmed: message.kind == "disarmed")
        case "rejected":
            let error = WindowRecoveryError.rejected(message.reason ?? "Recovery command rejected.")
            let callback = started; started = nil; callback?(.failure(error))
            operations.removeValue(forKey: message.sequence)?(.failure(error))
            finishes.removeValue(forKey: message.sequence)?(.failure(error))
            if message.reason == "admission" { childExited() }
        default: break
        }
    }
    private func failNormalCommands(_ error: Error) {
        let start = started; started = nil; start?(.failure(error))
        let pending = operations.values; operations.removeAll(); pending.forEach { $0(.failure(error)) }
        let final = finishes.values; finishes.removeAll(); final.forEach { $0(.failure(error)) }
    }
    private func childExited() {
        guard !isTerminal else { return }
        heartbeat?.invalidate(); heartbeat = nil
        if !FileManager.default.fileExists(atPath: directory.path) {
            terminateSession(); return
        }
        recoveryPending = true; failNormalCommands(WindowRecoveryError.pending("Recovery helper disconnected; the journal remains pending."))
        startMonitor()
    }
    private func startMonitor() {
        guard monitor == nil else { return }
        let monitorTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.observeOrResume() }
        monitor = monitorTimer
        RunLoop.main.add(monitorTimer, forMode: .common)
    }
    private func observeOrResume() {
        guard !isTerminal, !reclaimingHelper else { return }
        guard FileManager.default.fileExists(atPath: directory.path) else { terminateSession(); return }
        let state = try? RecoveryJournal.read(RecoveryJournalState.self, from: directory.appendingPathComponent("state.json"))
        let expectedSHA = try? RecoveryJournal.requestSHA(at: directory)
        let validState = state?.generation == request.generation && state?.requestSHA == expectedSHA
        if let state = state, validState, state.terminal {
            let outcome: Result<CGRect, Error> = state.phase == "targetGone" ? .failure(WindowRecoveryError.identityChanged) : .success(state.lastFrame ?? request.source)
            terminateSession(outcome: outcome, disarmed: state.phase == "disarmed"); return
        }
        let launchRecord = try? RecoveryJournal.read(RecoveryHelperLaunch.self, from: directory.appendingPathComponent("launch.json"))
        let validLaunch = launchRecord?.generation == request.generation && launchRecord?.requestSHA == expectedSHA
        if let helper = WindowRecoveryHelperSelection.select(journal: validState ? state?.helper : nil, launch: validLaunch ? launchRecord?.helper : nil),
           let hash = expectedSHA {
            helperIdentity = helper
            let heartbeat = try? RecoveryJournal.read(RecoveryHelperHeartbeat.self, from: directory.appendingPathComponent("helper-heartbeat.json"))
            let validHeartbeat = heartbeat?.generation == request.generation && heartbeat?.requestSHA == hash && heartbeat?.helper == helper
            if helperHealth.shouldReclaim(at: ProcessInfo.processInfo.systemUptime, heartbeatUptime: validHeartbeat ? heartbeat?.uptime : nil) {
                reclaim(helper: helper, requestSHA: hash)
            }
            startMonitor(); return
        }
        if let process = process, process.isRunning { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextLaunch else { return }
        launchAttempt += 1; nextLaunch = now + min(10, pow(2, Double(min(launchAttempt, 4))))
        do { try launch() } catch { recoveryPending = true; startMonitor() }
    }
    private func reclaim(helper: WindowRecoveryProcessIdentity, requestSHA: String) {
        guard !reclaimingHelper,
              requestSHA == (try? RecoveryJournal.requestSHA(at: directory)),
              helper.uid == getuid(), helper.executable == request.parent.executable,
              helper.pid != request.parent.pid, helper.pid != request.target.pid, helper.pid != getpid() else { return }
        reclaimingHelper = true; recoveryPending = true
        failNormalCommands(WindowRecoveryError.pending("Recovery helper stopped responding; restoring its pending transaction."))
        let request = self.request, directory = self.directory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            func stillOwned() -> Bool {
                guard helper.status() == .same else { return false }
                let current = try? RecoveryJournal.read(RecoveryJournalState.self, from: directory.appendingPathComponent("state.json"))
                if let current = current {
                    guard current.generation == request.generation, current.requestSHA == requestSHA, !current.terminal else { return false }
                }
                let launch = try? RecoveryJournal.read(RecoveryHelperLaunch.self, from: directory.appendingPathComponent("launch.json"))
                let validLaunch = launch?.generation == request.generation && launch?.requestSHA == requestSHA
                return WindowRecoveryHelperSelection.select(journal: current?.helper, launch: validLaunch ? launch?.helper : nil) == helper
            }
            if stillOwned() { _ = Darwin.kill(helper.pid, SIGTERM) }
            for _ in 0..<6 {
                if helper.status() != .same { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if stillOwned() { _ = Darwin.kill(helper.pid, SIGKILL) }
            for _ in 0..<24 {
                if helper.status() != .same { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            let gone = helper.status() == .gone || helper.status() == .changed
            var leaseAvailable = false
            if gone {
                // Closing this probe lock before relaunch lets the replacement
                // acquire it itself. Another winner still excludes every write.
                if let probe = try? WindowRecoveryFileLock(url: RecoveryJournal.lockURL(request)) {
                    withExtendedLifetime(probe) { leaseAvailable = true }
                }
            }
            let canResume = gone && leaseAvailable
            DispatchQueue.main.async {
                guard let self = self, !self.isTerminal else { return }
                self.reclaimingHelper = false
                if canResume {
                    self.helperIdentity = nil; self.nextLaunch = 0
                    self.observeOrResume()
                }
            }
        }
    }
    private func terminateSession(outcome: Result<CGRect, Error> = .failure(WindowRecoveryError.transportClosed), disarmed: Bool = false) {
        guard !isTerminal else { return }
        isTerminal = true; recoveryPending = false
        heartbeat?.invalidate(); monitor?.invalidate(); heartbeat = nil; monitor = nil
        responsePipe?.fileHandleForReading.readabilityHandler = nil
        if let handle = commandPipe?.fileHandleForWriting {
            sendQueue.async { handle.closeFile() }
        }
        let successfulFinishes = disarmed ? Array(finishes.values) : []
        if disarmed { finishes.removeAll() }
        Self.reservations.removeValue(forKey: request.generation); Self.sessions.removeValue(forKey: request.generation)
        RecoveryJournal.remove(directory)
        failNormalCommands(WindowRecoveryError.transportClosed)
        successfulFinishes.forEach { $0(.success(())) }
        let callbacks = recoveries; recoveries.removeAll(); callbacks.forEach { $0(outcome) }
        if !Self.isWindowReserved(targetWindowID) {
            let actions = Self.releaseActions.removeValue(forKey: targetWindowID) ?? []
            actions.forEach { $0() }
        }
        DispatchQueue.main.async {
            if Self.prewarmingEnabled && !Self.prewarmRetryPolicy.isExhausted { Self.ensurePrewarm() }
        }
    }
}

enum RecoveryAXFailure: Error {
    case transient(AXError), mismatch, wideCorner, targetGone, identityUnavailable, identityConflict

    static func identityReadFailure(_ error: AXError, observed: Int64, expected: Int64) -> RecoveryAXFailure? {
        guard error == .success, observed > 0 else { return .identityUnavailable }
        return observed == expected ? nil : .identityConflict
    }
}

/// Polling has no mutation callback: an accepted write is never repeated when
/// identity temporarily becomes unreadable during its existing readback budget.
enum WindowRecoveryReadback {
    static func verify(timeout: TimeInterval,
                       now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                       pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                       read: (Float) throws -> CGRect?) throws -> CGRect {
        let deadline = now() + timeout
        var samples = 0
        var lastFailure: RecoveryAXFailure?
        while now() < deadline {
            do {
                if let frame = try read(Float(min(0.15, max(0.001, deadline-now())))) {
                    lastFailure = nil
                    samples += 1
                    if samples == 2 { return frame }
                } else { samples = 0; lastFailure = .mismatch }
            } catch RecoveryAXFailure.transient(let error) { samples = 0; lastFailure = .transient(error) }
              catch RecoveryAXFailure.mismatch { samples = 0; lastFailure = .mismatch }
              catch RecoveryAXFailure.identityUnavailable { samples = 0; lastFailure = .identityUnavailable }
            let remaining = deadline-now()
            if remaining > 0 { pause(min(0.016, remaining)) }
        }
        throw lastFailure ?? RecoveryAXFailure.mismatch
    }
}

private final class RecoveryAXTarget {
    private let request: RecoveryRequest
    private var window: AXUIElement?
    init(request: RecoveryRequest) { self.request = request }

    private func identityFailure(_ failure: RecoveryAXFailure, stage: String, error: AXError? = nil,
                                 observed: Int64? = nil, expected: Int64? = nil) -> RecoveryAXFailure {
        var fields: [String: Any] = ["windowID": request.windowID, "stage": stage, "failure": String(describing: failure)]
        if let error = error { fields["axError"] = error.rawValue }
        if let observed = observed { fields["observedIdentity"] = observed }
        if let expected = expected { fields["expectedIdentity"] = expected }
        RecoveryTrace.event("identityCheckFailed", fields: fields)
        return failure
    }
    private func validateProcess() throws {
        switch request.target.status() {
        case .same: return
        case .changed: throw identityFailure(.targetGone, stage: "processChanged")
        case .gone: throw identityFailure(.targetGone, stage: "processGone")
        case .unavailable: throw identityFailure(.identityUnavailable, stage: "processLookup")
        }
    }
    private func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        guard error == .success, let result = result else { throw RecoveryAXFailure.transient(error) }
        return result
    }
    func resolve(timeout: Float = 0.15) throws -> AXUIElement {
        try validateProcess()
        if let window = window {
            AXUIElementSetMessagingTimeout(window, timeout)
            var identifier: CGWindowID = 0
            let error = _AXUIElementGetWindow(window, &identifier)
            if let failure = RecoveryAXFailure.identityReadFailure(error, observed: Int64(identifier), expected: Int64(request.windowID)) {
                _ = identityFailure(failure, stage: "retainedWindowID", error: error,
                                    observed: Int64(identifier), expected: Int64(request.windowID))
                // Never rebind a retained reference after an ambiguous invalidation.
                // A failed absence check must not downgrade a known conflict to
                // a retryable error or discard the original window's journal.
                if case .identityConflict = failure {
                    if (try? confirmsWindowGone()) == true { throw RecoveryAXFailure.targetGone }
                    throw failure
                }
                if try confirmsWindowGone() { throw RecoveryAXFailure.targetGone }
                throw failure
            }
            return window
        }
        let app = AXUIElementCreateApplication(request.target.pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let windows = try value(app, kAXWindowsAttribute) as? [AXUIElement] else { throw RecoveryAXFailure.mismatch }
        let matches = windows.filter { candidate in
            var identifier: CGWindowID = 0
            return _AXUIElementGetWindow(candidate, &identifier) == .success && identifier == request.windowID
        }
        guard matches.count == 1 else {
            if matches.isEmpty, try confirmsWindowGone() { throw RecoveryAXFailure.targetGone }
            throw identityFailure(matches.isEmpty ? .identityUnavailable : .identityConflict, stage: "windowEnumeration")
        }
        let window = matches[0]
        AXUIElementSetMessagingTimeout(window, timeout)
        var owner: pid_t = 0
        let ownerError = AXUIElementGetPid(window, &owner)
        if let failure = RecoveryAXFailure.identityReadFailure(ownerError, observed: Int64(owner), expected: Int64(request.target.pid)) {
            throw identityFailure(failure, stage: "windowOwnerPID", error: ownerError,
                                  observed: Int64(owner), expected: Int64(request.target.pid))
        }
        for attribute in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            let error = AXUIElementIsAttributeSettable(window, attribute as CFString, &settable)
            guard error == .success, settable.boolValue else { throw RecoveryAXFailure.transient(error) }
        }
        self.window = window
        return window
    }
    private func confirmsWindowGone() throws -> Bool {
        try validateProcess()
        // Absence is terminal only after two successful AX enumerations AND two
        // successful CG snapshots. A timeout or a filtered list is not absence.
        for index in 0..<2 {
            let app = AXUIElementCreateApplication(request.target.pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            guard let windows = try value(app, kAXWindowsAttribute) as? [AXUIElement],
                  let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return false }
            if rows.contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == request.windowID && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == request.target.pid }) { return false }
            for candidate in windows {
                var id: CGWindowID = 0
                guard _AXUIElementGetWindow(candidate, &id) == .success else { return false }
                if id == request.windowID { return false }
            }
            if index == 0 { Thread.sleep(forTimeInterval: 0.05) }
        }
        return true
    }
    func read(timeout: Float = 0.15) throws -> (ax: CGRect, cg: CGRect) {
        let window = try resolve(timeout: timeout)
        let position = try value(window, kAXPositionAttribute), size = try value(window, kAXSizeAttribute)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { throw RecoveryAXFailure.mismatch }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { throw RecoveryAXFailure.mismatch }
        let frame = CGRect(origin: p, size: s)
        guard WindowRecoveryGeometry.valid(frame),
              let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let row = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == request.windowID && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == request.target.pid }),
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let cg = CGRect(dictionaryRepresentation: bounds as CFDictionary), WindowRecoveryGeometry.valid(cg) else { throw RecoveryAXFailure.mismatch }
        return (frame, cg)
    }
    private func write(attribute: WindowParkingOperation.Attribute, frame: CGRect, timeout: Float) throws {
        let window = try resolve(timeout: timeout)
        try validateProcess()
        var point = frame.origin, size = frame.size
        let value: AXValue?
        let name: String
        switch attribute {
        case .position: value = AXValueCreate(.cgPoint, &point); name = kAXPositionAttribute
        case .size: value = AXValueCreate(.cgSize, &size); name = kAXSizeAttribute
        }
        guard let value = value else { throw RecoveryAXFailure.mismatch }
        let began = ProcessInfo.processInfo.systemUptime
        let result = AXUIElementSetAttributeValue(window, name as CFString, value)
        RecoveryTrace.event("axWrite", fields: ["attribute": name, "durationMilliseconds": (ProcessInfo.processInfo.systemUptime-began)*1000,
                                               "axError": result.rawValue, "windowID": request.windowID])
        guard result == .success else { throw RecoveryAXFailure.transient(result) }
    }
    func perform(_ operation: WindowParkingOperation, timeout: TimeInterval, departure: CGRect?,
                 displays: @escaping () -> [WindowParkingDisplay]) throws -> CGRect {
        guard WindowRecoveryGeometry.valid(operation.frame) else { throw WindowRecoveryError.invalidRequest }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        RecoveryTrace.event("operation", fields: ["phase": operation.phase, "attribute": operation.attribute.rawValue, "windowID": request.windowID])
        do { try write(attribute: operation.attribute, frame: operation.frame, timeout: Float(min(0.25, timeout))) }
        catch RecoveryAXFailure.transient(let error) where error == .cannotComplete {
            // The server may have accepted this write. Observe its result without
            // issuing a duplicate mutation during this operation's deadline.
        }
        return try verify(expected: operation.frame, corner: operation.corner, initialParking: operation.phase == "initial-parking",
                          departure: departure, departureCover: operation.departureCover,
                          sourceResizeCover: operation.attribute == .size && !operation.corner
                              && operation.phase == "shrink-under-source-cover" ? request.source : nil,
                          timeout: max(0, deadline-ProcessInfo.processInfo.systemUptime), displays: displays)
    }
    func verify(expected: CGRect, corner: Bool = false, initialParking: Bool = false, departure: CGRect? = nil,
                departureCover: CGRect? = nil,
                releasedSource: Bool = false,
                sourceResizeCover: CGRect? = nil,
                timeout: TimeInterval = 0.6, displays: @escaping () -> [WindowParkingDisplay]) throws -> CGRect {
        var sawAX = false, sawCG = false
        var previousCoveredFrame: CGRect?
        let verified = try WindowRecoveryReadback.verify(timeout: timeout) { readTimeout in
            let current = try read(timeout: readTimeout)
            let screens = displays()
            if let cover = sourceResizeCover,
               WindowSourceCoverResize.accepts(actual: current.ax, requested: expected, source: cover),
               WindowSourceCoverResize.accepts(actual: current.cg, requested: expected, source: cover),
               WindowRecoveryGeometry.near(current.ax, current.cg, tolerance: 1) {
                let stable = previousCoveredFrame.map { WindowRecoveryGeometry.near($0, current.ax, tolerance: 1) } ?? false
                previousCoveredFrame = current.ax
                // Require a stable achieved frame as well as AX/WindowServer agreement.
                // The coordinator replans from it; no offscreen size check is relaxed.
                return stable ? current.ax : nil
            }
            previousCoveredFrame = nil
            if corner {
                let allowedDeparture = initialParking ? departure : nil
                let cover = initialParking ? departureCover : nil
                let axSafe = WindowRecoveryGeometry.safeParkingObservation(current.ax, departure: allowedDeparture, source: request.source, displays: screens, departureCover: cover)
                let cgSafe = WindowRecoveryGeometry.safeParkingObservation(current.cg, departure: allowedDeparture, source: request.source, displays: screens, departureCover: cover)
                guard axSafe && cgSafe else { throw RecoveryAXFailure.wideCorner }
            }
            // Parking acceptance includes the measured upward clamp. Do not
            // accidentally add the ordinary 2pt expected-y gate here.
            let axMatches = corner ? WindowParkingPlan.accepts(actual: current.ax, expected: expected, displays: screens) : WindowRecoveryGeometry.near(current.ax, expected)
            let cgMatches = corner ? WindowParkingPlan.accepts(actual: current.cg, expected: expected, displays: screens) : WindowRecoveryGeometry.near(current.cg, expected)
            if axMatches && !sawAX { sawAX = true; RecoveryTrace.event("firstAXMatch", fields: ["windowID": request.windowID, "corner": corner]) }
            if cgMatches && !sawCG { sawCG = true; RecoveryTrace.event("firstCGMatch", fields: ["windowID": request.windowID, "corner": corner]) }
            let sourceAdmission = releasedSource && expected == request.source && request.releasedSnap == true
            let visible = sourceAdmission ? WindowRecoveryGeometry.visibleReleasedSource : WindowRecoveryGeometry.visible
            let location = corner || (visible(current.ax, screens) && visible(current.cg, screens))
            if axMatches && cgMatches && WindowRecoveryGeometry.near(current.ax, current.cg, tolerance: 1) && location {
                return current.ax
            }
            return nil
        }
        RecoveryTrace.event("verified", fields: ["windowID": request.windowID, "corner": corner])
        return verified
    }
    func restore(source: CGRect, displays: @escaping () -> [WindowParkingDisplay]) throws -> CGRect {
        try WindowRecoveryRestoration.perform(source: source, displays: displays,
            read: { try self.read().ax },
            write: { try self.write(attribute: $0, frame: $1, timeout: 0.2) },
            verify: { try self.verify(expected: $0, timeout: 0.6, displays: displays) })
    }
}

private final class RecoveryHelperRuntime {
    private let request: RecoveryRequest
    private let directory: URL
    private let lock: WindowRecoveryFileLock
    private let target: RecoveryAXTarget
    private var state: RecoveryJournalState
    private var gate: WindowRecoveryCommandGate
    private var retry = WindowRecoveryRetryPolicy()
    private let worker = DispatchQueue(label: "Rectangle.WindowRecovery.AX", qos: .userInitiated)
    private let writer = DispatchQueue(label: "Rectangle.WindowRecovery.reply")
    private let reader = RecoveryLineReader()
    private var busy = false
    private var lastBeat = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var screens: [WindowParkingDisplay] = []
    private var repliesOpen = true
    private var inputClosed = false
    private var normalCompletionSequence: UInt64 = 0
    private var finished = false
    private var heartbeatSequence: UInt64 = 0
    private var lastHeartbeatPublication: TimeInterval = 0

    init(requestPath: String) throws {
        directory = URL(fileURLWithPath: requestPath).deletingLastPathComponent()
        guard directory.deletingLastPathComponent().resolvingSymlinksInPath() == RecoveryJournal.root.resolvingSymlinksInPath(),
              directory.lastPathComponent == directory.resolvingSymlinksInPath().lastPathComponent else { throw WindowRecoveryError.invalidRequest }
        request = try RecoveryJournal.read(RecoveryRequest.self, from: URL(fileURLWithPath: requestPath))
        guard request.schema == 1, request.generation.uuidString == directory.lastPathComponent,
              request.target.uid == getuid(), request.parent.uid == getuid(), request.target.pid != getpid(),
              WindowRecoveryGeometry.valid(request.source), WindowRecoveryGeometry.valid(request.destination),
              WindowRecoveryGeometry.valid(request.restorationFrame),
              !request.bootSession.isEmpty, request.bootSession == RecoveryJournal.bootSession(),
              let own = WindowRecoveryProcessIdentity.read(getpid()) else { throw WindowRecoveryError.invalidRequest }
        try RecoveryJournal.prepareRoot()
        lock = try WindowRecoveryFileLock(url: RecoveryJournal.lockURL(request))
        let hash = try RecoveryJournal.requestSHA(at: directory)
        if let existing = try? RecoveryJournal.read(RecoveryJournalState.self, from: directory.appendingPathComponent("state.json")) {
            guard existing.generation == request.generation, existing.requestSHA == hash else { throw WindowRecoveryError.invalidRequest }
            state = existing; state.helper = own
        } else {
            state = RecoveryJournalState(generation: request.generation, requestSHA: hash, helper: own, phase: "registering", possiblyMoved: false,
                                         lastFrame: nil, reason: nil, sequence: 0, attempts: 0,
                                         uptime: ProcessInfo.processInfo.systemUptime, wallTime: Date().timeIntervalSince1970)
        }
        gate = WindowRecoveryCommandGate(generation: request.generation)
        target = RecoveryAXTarget(request: request)
    }

    func start() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        refreshScreens()
        publishHeartbeat()
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = WindowRecoveryInput.readAvailable(from: handle)
            DispatchQueue.main.async { self?.receive(data) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        if state.terminal { finish(kind: state.phase, frame: state.lastFrame, sequence: 0); return }
        if state.phase != "registering" || request.parent.status() != .same {
            beginRecovery(reason: "Resuming pending recovery")
            return
        }
        busy = true
        worker.async { [self] in
            let result = Result { () -> CGRect in
                guard AXIsProcessTrusted(), request.parent.status() == .same else { throw WindowRecoveryError.invalidRequest }
                return try target.verify(expected: request.source, releasedSource: request.releasedSnap == true,
                                         timeout: 0.6, displays: screenSnapshot)
            }
            DispatchQueue.main.async { [self] in
                busy = false
                guard !gate.recovering else { return }
                switch result {
                case .success(let frame):
                    do {
                        state.phase = "armed"; state.lastFrame = frame; try persist()
                        RecoveryTrace.event("armed", fields: ["windowID": request.windowID])
                        reply("armed", sequence: 0, frame: frame)
                    } catch { rejectAdmission(error) }
                case .failure(let error): rejectAdmission(error)
                }
            }
        }
    }
    private func refreshScreens() { screens = WindowRecoveryGeometry.displaySnapshot() }
    private func publishHeartbeat() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastHeartbeatPublication >= 0.5, let helper = state.helper else { return }
        heartbeatSequence += 1; lastHeartbeatPublication = now
        let heartbeat = RecoveryHelperHeartbeat(generation: request.generation, requestSHA: state.requestSHA, helper: helper,
                                                sequence: heartbeatSequence, uptime: now)
        try? RecoveryJournal.write(heartbeat, to: directory.appendingPathComponent("helper-heartbeat.json"), durable: false)
    }
    private func screenSnapshot() -> [WindowParkingDisplay] {
        if Thread.isMainThread { return screens }
        return DispatchQueue.main.sync { screens }
    }
    private func persist() throws {
        state.uptime = ProcessInfo.processInfo.systemUptime; state.wallTime = Date().timeIntervalSince1970
        state.sequence = gate.lastSequence; state.attempts = retry.attempts
        try RecoveryJournal.write(state, to: directory.appendingPathComponent("state.json"))
    }
    fileprivate func receive(_ data: Data) {
        guard !finished else { return }
        if data.isEmpty {
            guard !inputClosed else { return }
            inputClosed = true; repliesOpen = false
            beginRecovery(reason: "Parent connection closed"); return
        }
        guard !inputClosed else { return }
        do {
            for message in try reader.consume(data) {
                let control = message.kind == "heartbeat" || message.kind == "recover"
                guard gate.accept(generation: message.generation, sequence: message.sequence, isRecovery: control) else {
                    if message.kind != "heartbeat" { reply("rejected", sequence: message.sequence, reason: "Stale command or recovery already active") }
                    continue
                }
                switch message.kind {
                case "heartbeat": lastBeat = ProcessInfo.processInfo.systemUptime
                case "recover": beginRecovery(reason: message.reason ?? "Recovery requested")
                case "perform":
                    guard let operation = message.operation, let timeout = message.timeout, timeout.isFinite, timeout > 0, timeout <= 2,
                          state.phase == "armed", !busy else { reply("rejected", sequence: message.sequence, reason: "Operation unavailable"); continue }
                    perform(operation, timeout: timeout, sequence: message.sequence)
                case "finish":
                    guard let frame = message.frame, WindowRecoveryGeometry.valid(frame), state.phase == "armed", !busy else {
                        reply("rejected", sequence: message.sequence, reason: "Final verification unavailable"); continue
                    }
                    verifyFinish(frame, sequence: message.sequence)
                default: beginRecovery(reason: "Invalid command")
                }
            }
        } catch { beginRecovery(reason: "Invalid recovery transport") }
    }
    private func perform(_ operation: WindowParkingOperation, timeout: TimeInterval, sequence: UInt64) {
        guard WindowRecoveryGeometry.valid(operation.frame) else { beginRecovery(reason: "Invalid operation geometry"); return }
        do {
            state.possiblyMoved = true; state.phase = "writing"; try persist()
        } catch { beginRecovery(reason: "Cannot persist mutation intent"); return }
        busy = true
        let departure = state.lastFrame
        worker.async { [self] in
            let result = Result { try target.perform(operation, timeout: timeout, departure: departure, displays: screenSnapshot) }
            DispatchQueue.main.async { [self] in
                busy = false
                guard !gate.recovering else { return }
                switch result {
                case .success(let frame):
                    state.lastFrame = frame; state.phase = "armed"
                    do { try persist(); reply("performed", sequence: sequence, frame: frame) }
                    catch { beginRecovery(reason: "Cannot persist verified frame") }
                case .failure(let error): handleFailure(error, reason: "Window operation needs recovery")
                }
            }
        }
    }
    private func verifyFinish(_ frame: CGRect, sequence: UInt64) {
        busy = true; normalCompletionSequence = sequence
        worker.async { [self] in
            let result = Result { try target.verify(expected: frame, timeout: 0.6, displays: screenSnapshot) }
            DispatchQueue.main.async { [self] in
                busy = false
                guard !gate.recovering else { return }
                switch result {
                case .success(let actual): finish(kind: "disarmed", frame: actual, sequence: sequence)
                case .failure(let error): handleFailure(error, reason: "Final placement did not verify")
                }
            }
        }
    }
    private func beginRecovery(reason: String) {
        guard !finished, !gate.recovering || state.phase != "recovering" else { return }
        let first = !gate.recovering
        gate.beginRecovery(); state.phase = "recovering"; state.reason = reason
        // Existing durable mutation intent remains sufficient if a later disk
        // failure prevents a phase update. Recovery must not stop for logging.
        try? persist()
        if first {
            RecoveryTrace.event("pending", fields: ["windowID": request.windowID, "reason": reason])
            reply("recovering", sequence: 0, reason: reason)
        }
    }
    private func tick() {
        guard !finished else { return }
        publishHeartbeat()
        refreshScreens()
        if !gate.recovering {
            switch request.parent.status() {
            case .gone, .changed: beginRecovery(reason: "Parent exited")
            case .same, .unavailable:
                if ProcessInfo.processInfo.systemUptime-lastBeat > 2 { beginRecovery(reason: "Main-thread heartbeat expired") }
            }
        }
        guard gate.recovering, !busy, retry.shouldProbe(at: ProcessInfo.processInfo.systemUptime) else { return }
        if !state.possiblyMoved { finish(kind: "cancelled", frame: nil, sequence: 0); return }
        busy = true
        worker.async { [self] in
            let result = Result { try target.restore(source: request.restorationFrame, displays: screenSnapshot) }
            DispatchQueue.main.async { [self] in
                busy = false
                switch result {
                case .success(let frame): retry.completed(); finish(kind: "recovered", frame: frame, sequence: 0)
                case .failure(let error):
                    if case RecoveryAXFailure.targetGone = error { finish(kind: "targetGone", frame: nil, sequence: 0) }
                    else { retry.failed(at: ProcessInfo.processInfo.systemUptime); state.reason = String(describing: error); try? persist() }
                }
            }
        }
    }
    private func handleFailure(_ error: Error, reason: String) {
        if case RecoveryAXFailure.targetGone = error { finish(kind: "targetGone", frame: nil, sequence: 0) }
        else { beginRecovery(reason: "\(reason): \(error)") }
    }
    private func rejectAdmission(_ error: Error) {
        reply("rejected", sequence: 0, reason: error.localizedDescription)
        finish(kind: "cancelled", frame: nil, sequence: 0)
    }
    private func reply(_ kind: String, sequence: UInt64, frame: CGRect? = nil, reason: String? = nil) {
        guard repliesOpen else { return }
        let message = RecoveryMessage(generation: request.generation, sequence: sequence, kind: kind, frame: frame,
                                      reason: reason, requestSHA: state.requestSHA, helper: state.helper)
        writer.async { [weak self] in
            if !recoveryWrite(message, to: STDOUT_FILENO) {
                DispatchQueue.main.async { self?.repliesOpen = false; self?.beginRecovery(reason: "Parent reply connection closed") }
            }
        }
    }
    private func finish(kind: String, frame: CGRect?, sequence: UInt64) {
        guard !finished else { return }
        state.phase = kind; state.lastFrame = frame
        do { try persist() }
        catch {
            RecoveryJournal.remove(directory)
            guard !FileManager.default.fileExists(atPath: directory.path) else {
                beginRecovery(reason: "Cannot retire recovery journal"); return
            }
        }
        RecoveryTrace.event("outcome", fields: ["windowID": request.windowID, "kind": kind, "attempts": retry.attempts])
        finished = true; timer?.invalidate()
        FileHandle.standardInput.readabilityHandler = nil
        reply(kind, sequence: sequence, frame: frame)
        writer.async { [directory] in
            RecoveryJournal.remove(directory)
            exit(0)
        }
    }
}

private final class RecoveryStandbyRuntime {
    private let parent: WindowRecoveryProcessIdentity
    private let helper: WindowRecoveryProcessIdentity
    private let generation = UUID()
    private var sequence: UInt64 = 0
    private var lastBeat = ProcessInfo.processInfo.systemUptime
    private var data = Data()
    private var timer: Timer?
    private var runtime: RecoveryHelperRuntime?
    private let writer = DispatchQueue(label: "Rectangle.WindowRecovery.standby-reply")

    init() throws {
        guard let parent = WindowRecoveryProcessIdentity.read(getppid()), let helper = WindowRecoveryProcessIdentity.read(getpid()),
              parent.uid == helper.uid, parent.executable == helper.executable, parent.pid != helper.pid else { throw WindowRecoveryError.identityChanged }
        self.parent = parent; self.helper = helper
    }
    func start() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        _ = NSScreen.screens
        // No target lookup, recovery directory, journal or lock exists in standby.
        reply("standby-ready")
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = WindowRecoveryInput.readAvailable(from: handle)
            DispatchQueue.main.async { self?.receive(data) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }
    private func tick() {
        guard runtime == nil else { return }
        guard parent.status() == .same, ProcessInfo.processInfo.systemUptime-lastBeat <= 3 else { exit(0) }
        reply("standby-heartbeat")
    }
    private func reply(_ kind: String) {
        sequence += 1
        let message = RecoveryMessage(generation: generation, sequence: sequence, kind: kind, helper: helper, parent: parent,
                                      uptime: ProcessInfo.processInfo.systemUptime)
        writer.async { if !recoveryWrite(message, to: STDOUT_FILENO) { exit(0) } }
    }
    private func receive(_ chunk: Data) {
        if let runtime = runtime { runtime.receive(chunk); return }
        guard !chunk.isEmpty else { exit(0) }
        data.append(chunk)
        guard data.count <= 131_072 else { exit(1) }
        while let newline = data.firstIndex(of: 10) {
            var line = Data(data[..<newline]); data.removeSubrange(...newline)
            if let runtime = runtime { line.append(10); runtime.receive(line); continue }
            guard let command = try? RecoveryJournal.decoder.decode(RecoveryStandbyCommand.self, from: line),
                  command.parent == parent, parent.status() == .same else { exit(1) }
            switch command.kind {
            case "heartbeat": lastBeat = ProcessInfo.processInfo.systemUptime
            case "prepare":
                guard let path = command.requestPath else { exit(1) }
                timer?.invalidate(); timer = nil
                // Complete all standby replies before any transaction can park.
                // Their EOF behavior is intentionally exit-only while idle.
                writer.sync { }
                do {
                    let claimed = try RecoveryHelperRuntime(requestPath: path)
                    runtime = claimed; claimed.start()
                    // A partial transaction command may follow prepare in this
                    // read. Move it to the transaction's parser before returning.
                    if !data.isEmpty { let pending = data; data.removeAll(); claimed.receive(pending) }
                } catch { exit(1) }
            default: exit(1)
            }
        }
    }
}

enum WindowRecoveryHelper {
    static func runStandby() -> Never {
        do {
            let standby = try RecoveryStandbyRuntime()
            standby.start()
            withExtendedLifetime(standby) { CFRunLoopRun() }
        } catch { }
        exit(1)
    }

    static func run(requestPath: String) -> Never {
        do {
            let runtime = try RecoveryHelperRuntime(requestPath: requestPath)
            runtime.start()
            withExtendedLifetime(runtime) { CFRunLoopRun() }
        } catch {
            // No AX writes can occur before constructor validation and locking.
            let directory = URL(fileURLWithPath: requestPath).deletingLastPathComponent()
            if directory.deletingLastPathComponent().resolvingSymlinksInPath() == RecoveryJournal.root.resolvingSymlinksInPath(),
               (try? RecoveryJournal.read(RecoveryJournalState.self, from: directory.appendingPathComponent("state.json"))) == nil {
                RecoveryJournal.remove(directory)
            }
        }
        exit(1)
    }
}
