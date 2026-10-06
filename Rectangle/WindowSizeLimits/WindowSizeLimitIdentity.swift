import Cocoa

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
