/// ConfigFileManager.swift

import Foundation

/// Keeps a human-editable JSON config file in sync with Rectangle's preferences,
// Bidirectional with debounce and other robustness measures
final class ConfigFileManager {
    static let shared = ConfigFileManager()

    static let configFileName = "RectangleConfig.json"

    /// Debounce window that coalesces bursts of preference changes into a single write.
    private static let writeDebounce: TimeInterval = 0.4

    /// How long after our own write to keep ignoring watcher events it caused.
    private static let selfWriteGrace: TimeInterval = 0.2

    private var source: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var pendingWrite: DispatchWorkItem?

    /// True while applying the file's contents to `UserDefaults`, so the change
    /// notifications that produces don't immediately schedule a write back.
    private var isApplyingFromFile = false

    /// True briefly around our own write so watcher isn't confused
    private var isWritingToFile = false

    private init() {}

    static func defaultFolderURL() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Rectangle", isDirectory: true)
    }

    var folderURL: URL? {
        if let path = Defaults.configFileFolder.value, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultFolderURL()
    }

    var fileURL: URL? {
        folderURL?.appendingPathComponent(Self.configFileName)
    }

    var isEnabled: Bool {
        Defaults.configFileEnabled.userEnabled
    }

    /// Called once at launch, before the managers that read preferences are
    /// created, so an externally-provided file is applied up front.
    func startIfEnabled() {
        guard isEnabled else { return }
        begin()
    }

    /// Turn the feature on/off (and optionally relocate it) from the settings UI.
    func setEnabled(_ enabled: Bool, folder: URL? = nil) {
        stop()
        if let folder {
            Defaults.configFileFolder.value = folder.path
        }
        Defaults.configFileEnabled.enabled = enabled
        guard enabled else { return }
        begin()
    }

    /// Flush any pending write synchronously. Call on app termination.
    func flush() {
        guard isEnabled, pendingWrite != nil else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        writeToFile()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
        pendingWrite?.cancel()
        pendingWrite = nil
        stopWatching()
    }

    private func begin() {
        guard let fileURL else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            applyFromFile()
        } else {
            // Seed the file from the current preferences.
            writeToFile()
        }
        startWatching()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification,
                                               object: nil)
    }

    private func applyFromFile() {
        guard let fileURL else { return }
        isApplyingFromFile = true
        // `Defaults.load` applies the file's values to `UserDefaults` and posts
        // `configImported` so the running app reloads. 
        Defaults.load(fileUrl: fileURL)
        // Defer clearing the guard so any change notifications synchronously
        // produced by the load are still SUPPRESSED.
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingFromFile = false
        }
    }

    @objc private func preferencesChanged() {
        guard isEnabled, !isApplyingFromFile else { return }
        scheduleWrite()
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeToFile()
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDebounce, execute: work)
    }

    private func writeToFile() {
        pendingWrite = nil
        guard let fileURL, let folderURL, let json = Defaults.encoded() else { return }

        isWritingToFile = true
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            // Non-atomic write keeps the same inode, so our own watch sees a
            // `.write` event (which we ignore) rather than a `.rename`/`.delete`.
            try json.write(to: fileURL, atomically: false, encoding: .utf8)
        } catch {
            Logger.log("Unable to write config file at \(fileURL.path): \(error.localizedDescription)")
        }
        // Clear the self-write guard once the watcher has had a chance to fire.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.selfWriteGrace) { [weak self] in
            self?.isWritingToFile = false
        }
    }

    private func startWatching() {
        guard source == nil, let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Logger.log("Unable to watch config file at \(fileURL.path)")
            return
        }
        watchedDescriptor = descriptor

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .link, .revoke],
            queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            self.handleFileEvent(src.data)
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.watchedDescriptor, fd >= 0 {
                close(fd)
            }
            self?.watchedDescriptor = -1
        }
        source = src
        src.resume()
    }

    private func handleFileEvent(_ events: DispatchSource.FileSystemEvent) {
        // Seems to be our own in-place write.
        if isWritingToFile { return }
        guard isEnabled else { return }

        // Editors typically save atomically, replacing the inode. The old watch
        // is now stale, so re-establish it on the new file before reloading.
        if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
            stopWatching()
            applyFromFile()
            startWatching()
        } else {
            applyFromFile()
        }
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }
}
