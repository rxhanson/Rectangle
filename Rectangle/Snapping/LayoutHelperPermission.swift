import Cocoa
import ScreenCaptureKit

/// The permission request is reachable only after the user accepts the explanation.
/// Injected actions let tests cover denial and cancellation without changing TCC.
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

enum LayoutHelperPermission {
    private static var requesting = false
    static var previewsSupported: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    static var previewsAllowed: Bool {
        previewsSupported && CGPreflightScreenCaptureAccess()
    }

    enum Feature { case layoutHelper, windowDivider }

    static func explanationAlert(for feature: Feature = .layoutHelper) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch feature {
        case .layoutHelper:
            alert.messageText = "Enable window thumbnails?"
            alert.informativeText = "Screen Recording access lets Layout Helper show window thumbnails. Otherwise, it uses icons and titles. No images are saved or audio captured."
            alert.addButton(withTitle: "Enable Previews")
            alert.addButton(withTitle: "Use Icons and Titles")
        case .windowDivider:
            alert.messageText = "Enable enhanced divider transitions?"
            alert.informativeText = "A temporary screenshot hides window changes while resizing. Requires Screen Recording access; nothing is saved."
            alert.addButton(withTitle: "Enable Enhanced Transitions")
            alert.addButton(withTitle: "Use Standard Transitions")
        }
        return alert
    }

    /// Keep the UI responsive while ScreenCaptureKit waits for the system consent dialog.
    /// Enumeration requests access but does not capture images or start a recording.
    static func guideIfNeeded(for feature: Feature = .layoutHelper, completion: @escaping () -> Void = {}) {
        guard #available(macOS 14, *), !requesting else { completion(); return }
        requesting = true
        Task { @MainActor in
            defer { requesting = false; completion() }
            let outcome = await LayoutHelperPermissionFlow(
                isAllowed: { previewsAllowed },
                explain: {
                    NSApp.activate(ignoringOtherApps: true)
                    return explanationAlert(for: feature).runModal() == .alertFirstButtonReturn
                },
                request: {
                    NSLog("Layout Helper: requesting ScreenCaptureKit access for %@", Bundle.main.bundleIdentifier ?? "Rectangle")
                    do {
                        _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                        NSLog("Layout Helper: ScreenCaptureKit access succeeded")
                        return true
                    } catch {
                        let error = error as NSError
                        NSLog("Layout Helper: ScreenCaptureKit access failed (%@, %ld)", error.domain, error.code)
                        return false
                    }
                },
                openSettings: {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    if !NSWorkspace.shared.open(url) {
                        AlertUtil.oneButtonAlert(question: "Enable Screen Recording for Rectangle",
                            text: "Enable Rectangle in System Settings → Privacy & Security → Screen & System Audio Recording.")
                    }
                }
            ).run()
            if feature == .windowDivider, outcome == .iconsOnly {
                Defaults.windowDividerEnhanced.enabled = false
            }
        }
    }
}
