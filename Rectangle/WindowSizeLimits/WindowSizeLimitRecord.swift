import Cocoa

struct WindowSizeLimitRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var identity: WindowSizeLimitIdentity
    var appName: String
    var evidence: WindowSizeEvidence
}
