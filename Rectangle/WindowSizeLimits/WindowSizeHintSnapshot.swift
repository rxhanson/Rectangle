import Cocoa

/// Capture on the store's owner thread, then validate with bounded AX metadata
/// on a worker. No mutable store or AccessibilityElement is read by this value.
struct WindowSizeHintSnapshot {
    let evidence: WindowSizeEvidence
    let lifetime: TimeInterval?
    let cancellation: AccessibilityReadCancellation?

    var isCurrent: Bool { cancellation?.isCurrent != false }

    func minimum(reported: CGSize?, current: CGSize, now: TimeInterval) -> CGSize? {
        guard isCurrent, lifetime.map({ now - evidence.learnedAt > $0 }) != true,
              evidence.reported == Self.normalized(reported) else { return nil }
        var learned = evidence.learned
        if current.width.isFinite, current.height.isFinite, current.width > 0, current.height > 0 {
            if current.width + 2 < learned.width { learned.width = 0 }
            if current.height + 2 < learned.height { learned.height = 0 }
        }
        return Self.normalized(learned)
    }

    private static func normalized(_ size: CGSize?) -> CGSize? {
        guard let size else { return nil }
        let width = size.width.isFinite && size.width > 0 ? size.width : 0
        let height = size.height.isFinite && size.height > 0 ? size.height : 0
        return width > 0 || height > 0 ? CGSize(width: width, height: height) : nil
    }
}
