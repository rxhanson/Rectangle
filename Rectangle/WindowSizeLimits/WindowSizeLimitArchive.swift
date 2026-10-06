import Cocoa

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
