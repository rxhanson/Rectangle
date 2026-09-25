import Cocoa

struct WindowSizeEvidence: Codable, Equatable {
    var reported: CGSize?
    var learned: CGSize
    var learnedAt: TimeInterval
    var confirmations: Int = 2
    var requested: CGSize = .zero
    var achieved: CGSize = .zero
    var source: String = "verified-placement"

    var isValid: Bool {
        learned.width.isFinite && learned.height.isFinite && learned.width >= 0 && learned.height >= 0
            && (learned.width > 0 || learned.height > 0)
            && learnedAt.isFinite && confirmations >= 2
            && requested.width.isFinite && requested.height.isFinite
            && achieved.width.isFinite && achieved.height.isFinite
            && requested.width > 0 && requested.height > 0 && achieved.width > 0 && achieved.height > 0
            && (reported.map { $0.width.isFinite && $0.height.isFinite && $0.width >= 0 && $0.height >= 0 } ?? true)
    }
}

/// The live identity survives a Rectangle restart, but not an app relaunch or
/// login. Structural metadata can invalidate a hint for a changed live window.
/// Titles, document URLs and screen positions are deliberately not identifiers.
struct WindowSizeLimitIdentity: Codable, Equatable {
    var bundleID: String
    var appVersion: String
    var pid: Int32
    var launch: TimeInterval
    var session: String
    var windowID: UInt32
    var identifier: String?
    var role: String
    var subrole: String
    var structure: [String]

    func isSameLiveWindow(as other: Self) -> Bool {
        !session.isEmpty && windowID != 0 && bundleID == other.bundleID && appVersion == other.appVersion
            && session == other.session && pid == other.pid && launch == other.launch && windowID == other.windowID
    }
}

struct WindowSizeLimitRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var identity: WindowSizeLimitIdentity
    var appName: String
    var evidence: WindowSizeEvidence
}

/// Persistent records are separate from exported preferences and never become
/// an application-wide minimum. Only the same live window can use a hint.
struct WindowSizeLimitArchive: Codable {
    var version = 2
    private(set) var records: [WindowSizeLimitRecord] = []

    func match(_ identity: WindowSizeLimitIdentity) -> WindowSizeLimitRecord? {
        let exact = records.filter { $0.identity.isSameLiveWindow(as: identity) }
        if exact.count == 1 {
            let old = exact[0].identity
            return old.identifier == identity.identifier && old.role == identity.role
                && old.subrole == identity.subrole && old.structure == identity.structure ? exact[0] : nil
        }
        return nil
    }

    mutating func upsert(_ record: WindowSizeLimitRecord) {
        guard record.evidence.isValid else { return }
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.append(record) }
        if records.count > 128 {
            records.sort { $0.evidence.learnedAt > $1.evidence.learnedAt }
            records.removeLast(records.count - 128)
        }
    }

    mutating func remove(id: UUID) { records.removeAll { $0.id == id } }
    mutating func remove(bundleID: String) { records.removeAll { $0.identity.bundleID == bundleID } }
    mutating func clear() { records.removeAll() }

    static func decode(_ data: Data) -> Self? {
        guard data.count <= 4_194_304, let archive = try? JSONDecoder().decode(Self.self, from: data),
              archive.version == 2, archive.records.allSatisfy({ $0.evidence.isValid }),
              Set(archive.records.map(\.id)).count == archive.records.count else { return nil }
        return archive
    }
}
