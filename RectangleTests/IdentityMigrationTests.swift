/// IdentityMigrationTests.swift

import XCTest
@testable import Rectangle

final class IdentityMigrationTests: XCTestCase {

    private var oldDomain: String!
    private var newDomain: String!
    private var oldKey: String!
    private var newKey: String!
    private var marker: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        oldDomain = "com.perg593.chiva.test.old.\(id)"
        newDomain = "com.perg593.chiva.test.new.\(id)"
        oldKey = "\(oldDomain!).customLayouts"
        newKey = "\(newDomain!).customLayouts"
        marker = "\(newDomain!).identityMigrationCompleted"
        defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: oldDomain)
        defaults.removePersistentDomain(forName: newDomain)
        defaults.removeObject(forKey: marker)
        defaults.synchronize()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: oldDomain)
        defaults.removePersistentDomain(forName: newDomain)
        defaults.removeObject(forKey: marker)
        defaults.synchronize()
        super.tearDown()
    }

    private func runMigration() {
        IdentityMigration.runIfNeeded(
            standard: defaults,
            oldDomain: oldDomain,
            newDomain: newDomain,
            oldCustomLayoutsKey: oldKey,
            newCustomLayoutsKey: newKey,
            completedKey: marker
        )
    }

    func testEmptyOldDomainSetsMarkerOnly() {
        runMigration()
        XCTAssertTrue(defaults.bool(forKey: marker))
        XCTAssertNil(defaults.persistentDomain(forName: newDomain))
    }

    func testMigratesDomainAndRemapsCustomLayoutsKey() {
        let layoutData = Data([0x01, 0x02, 0x03])
        defaults.setPersistentDomain([
            "launchOnLogin": true,
            "gapSize": 8,
            oldKey!: layoutData
        ], forName: oldDomain)

        runMigration()

        let domain = defaults.persistentDomain(forName: newDomain)!
        XCTAssertEqual(domain["launchOnLogin"] as? Bool, true)
        XCTAssertEqual(domain["gapSize"] as? Int, 8)
        XCTAssertEqual(domain[newKey] as? Data, layoutData)
        XCTAssertNil(domain[oldKey])
        XCTAssertTrue(defaults.bool(forKey: marker))
        XCTAssertNotNil(defaults.persistentDomain(forName: oldDomain))
    }

    func testPartialNewDomainWinsOnConflict() {
        defaults.setPersistentDomain(["gapSize": 1], forName: oldDomain)
        defaults.setPersistentDomain(["gapSize": 99, "keepMe": true], forName: newDomain)

        runMigration()

        let domain = defaults.persistentDomain(forName: newDomain)!
        XCTAssertEqual(domain["gapSize"] as? Int, 99)
        XCTAssertEqual(domain["keepMe"] as? Bool, true)
    }

    func testSecondRunIsNoOp() {
        defaults.setPersistentDomain(["gapSize": 1], forName: oldDomain)
        runMigration()

        var domain = defaults.persistentDomain(forName: newDomain)!
        domain["gapSize"] = 42
        defaults.setPersistentDomain(domain, forName: newDomain)

        defaults.setPersistentDomain(["gapSize": 999], forName: oldDomain)
        runMigration()

        let after = defaults.persistentDomain(forName: newDomain)!
        XCTAssertEqual(after["gapSize"] as? Int, 42)
    }
}
