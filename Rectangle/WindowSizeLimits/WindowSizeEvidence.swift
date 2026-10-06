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
