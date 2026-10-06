import Cocoa
import ScreenCaptureKit

/// The permission request is reachable only after the user accepts the explanation.
@MainActor struct LayoutHelperPermissionFlow {
    enum Outcome: Equatable { case alreadyAllowed, iconsOnly, allowed, needsSettings }
    var isAllowed: () -> Bool
    var explain: () -> Bool
    var request: () async -> Bool
    var openSettings: () -> Void

    func run() async -> Outcome {
        if isAllowed() { return .alreadyAllowed }
        guard explain() else { return .iconsOnly }
        let granted = await request()
        if granted || isAllowed() { return .allowed }
        openSettings()
        return .needsSettings
    }
}
