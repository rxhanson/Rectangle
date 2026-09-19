import Cocoa

struct WindowSizeEvidence: Codable, Equatable {
    var reported: CGSize?
    var learned: CGSize
    var learnedAt: TimeInterval

    var isValid: Bool {
        learned.width.isFinite && learned.height.isFinite && learned.width >= 0 && learned.height >= 0
            && (learned.width > 0 || learned.height > 0)
            && learnedAt.isFinite
            && (reported.map { $0.width.isFinite && $0.height.isFinite && $0.width >= 0 && $0.height >= 0 } ?? true)
    }
}

/// The live identity survives a Rectangle restart, but not an app relaunch or
/// login. The optional accessibility identity can match a recreated window.
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

    func isSameIdentifiedWindow(as other: Self) -> Bool {
        guard let identifier, !identifier.isEmpty, !appVersion.isEmpty,
              !role.isEmpty, !subrole.isEmpty, !structure.isEmpty else { return false }
        return bundleID == other.bundleID && appVersion == other.appVersion && identifier == other.identifier
            && role == other.role && subrole == other.subrole && structure == other.structure
    }
}

struct WindowSizeLimitRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var identity: WindowSizeLimitIdentity
    var appName: String
    var evidence: WindowSizeEvidence
}

/// Persistent records are separate from exported preferences and never become
/// an application-wide minimum. Ambiguity in either the saved or live set blocks
/// fallback matching, including two windows with the same AXIdentifier.
struct WindowSizeLimitArchive: Codable {
    var version = 1
    private(set) var records: [WindowSizeLimitRecord] = []

    func match(_ identity: WindowSizeLimitIdentity, liveIdentities: [WindowSizeLimitIdentity]) -> WindowSizeLimitRecord? {
        let exact = records.filter { $0.identity.isSameLiveWindow(as: identity) }
        if exact.count == 1 {
            let old = exact[0].identity
            return old.identifier == identity.identifier && old.role == identity.role
                && old.subrole == identity.subrole && old.structure == identity.structure ? exact[0] : nil
        }
        guard exact.isEmpty else { return nil }
        let saved = records.filter { $0.identity.isSameIdentifiedWindow(as: identity) }
        guard saved.count == 1,
              liveIdentities.filter({ $0.isSameIdentifiedWindow(as: identity) }).count == 1 else { return nil }
        // A fallback must never steal a record from its still-existing window.
        guard !liveIdentities.contains(where: { $0.isSameLiveWindow(as: saved[0].identity) }) else { return nil }
        return saved[0]
    }

    mutating func upsert(_ record: WindowSizeLimitRecord) {
        guard record.evidence.isValid else { return }
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.append(record) }
    }

    mutating func remove(id: UUID) { records.removeAll { $0.id == id } }
    mutating func remove(bundleID: String) { records.removeAll { $0.identity.bundleID == bundleID } }
    mutating func clear() { records.removeAll() }

    static func decode(_ data: Data) -> Self? {
        guard data.count <= 4_194_304, let archive = try? JSONDecoder().decode(Self.self, from: data),
              archive.version == 1, archive.records.allSatisfy({ $0.evidence.isValid }),
              Set(archive.records.map(\.id)).count == archive.records.count else { return nil }
        return archive
    }
}
