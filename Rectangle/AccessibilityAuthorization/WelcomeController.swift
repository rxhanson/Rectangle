import Foundation

/// Keeps first-launch Welcome pending independently of Accessibility authorization.
final class WelcomeController {
    private let defaults: UserDefaults
    private let pendingKey = "welcomePending"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Run before version bookkeeping, which also runs before permission is granted.
    func prepareForLaunch() {
        if defaults.string(forKey: Defaults.lastVersion.key) == nil {
            defaults.set(true, forKey: pendingKey)
        }
    }

    func checkAccessibility(using authorization: AccessibilityAuthorization,
                            showWelcome: @escaping () -> Void,
                            onNewGrant: @escaping () -> Void) -> Bool {
        let alreadyTrusted = authorization.checkAccessibility {
            self.showPendingWelcome(showWelcome)
            onNewGrant()
        }
        if alreadyTrusted {
            showPendingWelcome(showWelcome)
        }
        return alreadyTrusted
    }

    private func showPendingWelcome(_ showWelcome: () -> Void) {
        if defaults.bool(forKey: pendingKey) {
            showWelcome()
            defaults.set(false, forKey: pendingKey)
        }
    }
}
