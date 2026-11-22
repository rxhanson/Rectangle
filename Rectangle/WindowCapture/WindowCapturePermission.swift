import Cocoa
import ScreenCaptureKit

enum WindowCapturePermission {
    static let changed = Notification.Name("windowCapturePermissionChanged")
    private static var checking = false
    private static var requesting = false
    private static var revision = 0
    private static var cachedAllowed = false
    private static var checkedAt: TimeInterval = -.infinity

    static var previewsSupported: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    static var previewsAllowed: Bool {
        guard previewsSupported else { return false }
        // Repeated preview updates should not each wait on the system permission service.
        if !checking, !requesting, ProcessInfo.processInfo.systemUptime - checkedAt > 1 {
            checking = true
            let previousRevision = revision
            DispatchQueue.global(qos: .utility).async {
                let allowed = CGPreflightScreenCaptureAccess()
                DispatchQueue.main.async {
                    checking = false
                    guard previousRevision == revision else { return }
                    setAllowed(allowed)
                }
            }
        }
        return cachedAllowed
    }

    private static func setAllowed(_ allowed: Bool) {
        let changedValue = cachedAllowed != allowed
        cachedAllowed = allowed
        checkedAt = ProcessInfo.processInfo.systemUptime
        if changedValue { NotificationCenter.default.post(name: changed, object: nil) }
    }

    static func guideIfNeeded(explanation: @escaping () -> NSAlert,
                              onDecline: @escaping () -> Void = {},
                              completion: @escaping () -> Void = {}) {
        guard #available(macOS 14, *), !requesting else { completion(); return }
        requesting = true
        revision += 1
        Task { @MainActor in
            defer { requesting = false; completion() }
            let outcome = await WindowCapturePermissionFlow(
                isAllowed: { CGPreflightScreenCaptureAccess() },
                explain: {
                    NSApp.activate(ignoringOtherApps: true)
                    return explanation().runModal() == .alertFirstButtonReturn
                },
                request: {
                    // Asking for shareable content requests consent without capturing a frame.
                    do {
                        _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                        return true
                    } catch {
                        return false
                    }
                },
                openSettings: {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    if !NSWorkspace.shared.open(url) {
                        AlertUtil.oneButtonAlert(question: String(localized: "Enable Screen Recording for Rectangle"),
                            text: String(localized: "Enable Rectangle in System Settings → Privacy & Security → Screen & System Audio Recording."))
                    }
                }
            ).run()
            setAllowed(outcome == .allowed)
            if outcome == .declined { onDecline() }
        }
    }
}

@MainActor struct WindowCapturePermissionFlow {
    enum Outcome { case allowed, declined, needsSettings }

    let isAllowed: () -> Bool
    let explain: () -> Bool
    let request: () async -> Bool
    let openSettings: () -> Void

    func run() async -> Outcome {
        if isAllowed() { return .allowed }
        guard explain() else { return .declined }
        if await request() || isAllowed() { return .allowed }
        openSettings()
        return .needsSettings
    }
}
