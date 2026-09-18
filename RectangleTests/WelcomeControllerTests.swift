import XCTest
@testable import Rectangle

final class WelcomeControllerTests: XCTestCase {
    private final class Authorization: AccessibilityAuthorization {
        var trusted = false
        var grant: (() -> Void)?

        override func checkAccessibility(completion: @escaping () -> Void) -> Bool {
            if !trusted {
                grant = completion
            }
            return trusted
        }
    }

    private func preferences() -> (String, UserDefaults) {
        let name = "RectangleWelcomeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (name, defaults)
    }

    func testReauthorizationPreservesReturningUsersResizeChoice() {
        let (_, defaults) = preferences()
        defaults.set("106", forKey: Defaults.lastVersion.key)
        defaults.set(SubsequentExecutionMode.resize.rawValue,
                     forKey: Defaults.subsequentExecutionMode.key)
        defaults.set(false, forKey: Defaults.alternateDefaultShortcuts.key)
        let welcome = WelcomeController(defaults: defaults)
        welcome.prepareForLaunch()
        let authorization = Authorization()
        var presentations = 0
        var grants = 0

        XCTAssertFalse(welcome.checkAccessibility(using: authorization, showWelcome: {
            presentations += 1
            // Model selecting Recommended in the real Welcome modal.
            defaults.set(SubsequentExecutionMode.acrossMonitor.rawValue,
                         forKey: Defaults.subsequentExecutionMode.key)
            defaults.set(true, forKey: Defaults.alternateDefaultShortcuts.key)
        }, onNewGrant: { grants += 1 }))
        XCTAssertNotNil(authorization.grant)
        authorization.grant?()

        XCTAssertEqual(grants, 1)
        XCTAssertEqual(presentations, 0)
        XCTAssertEqual(defaults.integer(forKey: Defaults.subsequentExecutionMode.key),
                       SubsequentExecutionMode.resize.rawValue)
        XCTAssertFalse(defaults.bool(forKey: Defaults.alternateDefaultShortcuts.key))
    }

    func testNewUserReceivesWelcomeOnEitherAuthorizationPath() {
        for alreadyTrusted in [false, true] {
            let (_, defaults) = preferences()
            let welcome = WelcomeController(defaults: defaults)
            welcome.prepareForLaunch()
            let authorization = Authorization()
            authorization.trusted = alreadyTrusted
            var presentations = 0
            var grants = 0

            XCTAssertEqual(welcome.checkAccessibility(using: authorization, showWelcome: {
                presentations += 1
            }, onNewGrant: { grants += 1 }), alreadyTrusted)
            if !alreadyTrusted {
                XCTAssertEqual(presentations, 0)
                XCTAssertNotNil(authorization.grant)
                authorization.grant?()
            }
            XCTAssertEqual(presentations, 1)
            XCTAssertEqual(grants, alreadyTrusted ? 0 : 1)

            authorization.trusted = true
            XCTAssertTrue(welcome.checkAccessibility(using: authorization, showWelcome: {
                presentations += 1
            }, onNewGrant: { XCTFail("Already trusted") }))
            XCTAssertEqual(presentations, 1)
        }
    }

    func testRestartBeforeFirstGrantRetainsPendingWelcome() {
        for trustedOnRestart in [false, true] {
            let (name, defaults) = preferences()
            var presentations = 0
            do {
                let firstLaunch = WelcomeController(defaults: defaults)
                firstLaunch.prepareForLaunch()
                // checkVersion records these before Accessibility has been granted.
                defaults.set("106", forKey: Defaults.lastVersion.key)
                defaults.set("106", forKey: Defaults.installVersion.key)
                XCTAssertFalse(firstLaunch.checkAccessibility(using: Authorization(), showWelcome: {
                    presentations += 1
                }, onNewGrant: { XCTFail("No grant before exit") }))
            }
            XCTAssertEqual(presentations, 0)

            let restarted = WelcomeController(defaults: UserDefaults(suiteName: name)!)
            restarted.prepareForLaunch()
            let authorization = Authorization()
            authorization.trusted = trustedOnRestart
            XCTAssertEqual(restarted.checkAccessibility(using: authorization, showWelcome: {
                presentations += 1
            }, onNewGrant: {}), trustedOnRestart)
            if !trustedOnRestart {
                XCTAssertNotNil(authorization.grant)
                authorization.grant?()
            }
            XCTAssertEqual(presentations, 1)
        }
    }
}
