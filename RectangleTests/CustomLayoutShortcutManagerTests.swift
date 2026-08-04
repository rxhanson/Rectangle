/// CustomLayoutShortcutManagerTests.swift
///
/// M2 unit tests for CustomLayoutShortcutManager, using fakes (no real monitor, no
/// real windows). Real shared-monitor coexistence + real-window apply are additionally
/// covered by the --divvy2-spike harness (Checks 8 & 9).

import XCTest
import MASShortcut
@testable import Rectangle

// MARK: - Fakes

private final class FakeMonitor: ShortcutMonitoring {
    private(set) var registered: [MASShortcut] = []
    private(set) var unregistered: [MASShortcut] = []
    var failIdentities = Set<ShortcutCycle.ShortcutIdentity>()

    func registerChord(_ shortcut: MASShortcut, action: @escaping () -> Void) -> Bool {
        if failIdentities.contains(ShortcutCycle.ShortcutIdentity(shortcut)) { return false }
        registered.append(shortcut); return true
    }
    func unregisterChord(_ shortcut: MASShortcut) { unregistered.append(shortcut) }

    func registerCount(_ s: MASShortcut) -> Int { registered.filter { same($0, s) }.count }
    func unregisterCount(_ s: MASShortcut) -> Int { unregistered.filter { same($0, s) }.count }
    func isOwned(_ s: MASShortcut) -> Bool { registerCount(s) > unregisterCount(s) }
    private func same(_ a: MASShortcut, _ b: MASShortcut) -> Bool {
        ShortcutCycle.ShortcutIdentity(a) == ShortcutCycle.ShortcutIdentity(b)
    }
}

private final class FakeTarget: CustomLayoutTarget {
    let visibleFrame: CGRect
    var applied: CGRect?
    init(_ vf: CGRect) { visibleFrame = vf }
    func apply(_ appKitRect: CGRect) { applied = appKitRect }
}
private final class FakeContext: CustomLayoutWindowContext {
    let target: FakeTarget
    init(_ vf: CGRect) { target = FakeTarget(vf) }
    func currentTarget() -> CustomLayoutTarget? { target }
}

final class CustomLayoutShortcutManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!      // store
    private var conflicts: UserDefaults!     // WindowAction conflict defaults
    private var monitor: FakeMonitor!
    private var context: FakeContext!
    private var disabled = false
    private var reclaimCount = 0

    override func setUp() {
        super.setUp()
        suiteName = "com.perg593.chiva.m2tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        conflicts = UserDefaults(suiteName: suiteName + ".conf")
        monitor = FakeMonitor()
        context = FakeContext(CGRect(x: 1920, y: 0, width: 1440, height: 900)) // offset/secondary
        disabled = false
        reclaimCount = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        conflicts.removePersistentDomain(forName: suiteName + ".conf")
        super.tearDown()
    }

    private func makeManager(store: CustomLayoutStore) -> CustomLayoutShortcutManager {
        CustomLayoutShortcutManager(
            store: store,
            reclaim: { [weak self] in self?.reclaimCount += 1 },
            windowContext: context,
            conflictDefaults: conflicts,
            monitor: monitor,
            isShortcutsDisabled: { [weak self] in self?.disabled ?? false })
    }

    private func chord(_ keyCode: Int, _ flags: NSEvent.ModifierFlags = [.command, .control, .option]) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: flags)
    }
    private func layout(_ name: String, _ shortcut: MASShortcut?, _ id: UUID = UUID()) -> CustomLayout {
        CustomLayout(id: id, name: name, rect: NormalizedRect(x: 0, y: 0, w: 0.5, h: 1),
                     hotkey: shortcut.map { HotkeyData($0) })
    }
    private func injectWindowAction(_ shortcut: MASShortcut, _ action: WindowAction) {
        let t = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        conflicts.set(t.reverseTransformedValue(shortcut), forKey: action.name)
    }

    // MARK: register / noHotkey / monitor-failure / custom-dup

    func testRegistersFromStore() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let a = layout("a", chord(96)), b = layout("b", chord(97)), noKey = layout("c", nil)
        store.add(a); store.add(b); store.add(noKey)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertEqual(mgr.outcomes[a.id], .registered)
        XCTAssertEqual(mgr.outcomes[b.id], .registered)
        XCTAssertEqual(mgr.outcomes[noKey.id], .noHotkey)
        XCTAssertEqual(monitor.registered.count, 2)
    }

    func testMonitorFailure() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let a = layout("a", chord(96))
        store.add(a)
        monitor.failIdentities = [ShortcutCycle.ShortcutIdentity(a.hotkey!.toMASShortcut())]
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertEqual(mgr.outcomes[a.id], .monitorRegistrationFailed)
    }

    func testCustomDuplicateRejected() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let a = layout("a", chord(96)), b = layout("b", chord(96)) // same chord
        store.add(a); store.add(b)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertEqual(mgr.outcomes[a.id], .registered)
        XCTAssertEqual(mgr.outcomes[b.id], .conflictCustomLayout(a.id))
        XCTAssertEqual(monitor.registered.count, 1)
    }

    // MARK: WindowAction conflict (static) + dynamic yield + reclaim

    func testWindowActionConflictStatic() {
        injectWindowAction(chord(123, [.control, .option]), .leftHalf)
        let store = CustomLayoutStore(userDefaults: defaults)
        let a = layout("a", chord(123, [.control, .option]))
        store.add(a)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertEqual(mgr.outcomes[a.id], .conflictWindowAction(WindowAction.leftHalf.name))
        XCTAssertEqual(monitor.registerCount(a.hotkey!.toMASShortcut()), 0, "no monitor call for a conflicting chord")
    }

    func testDynamicYieldAndReclaimOnce() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let x = layout("x", chord(101)), y = layout("y", chord(103))
        store.add(x); store.add(y)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertTrue(monitor.isOwned(x.hotkey!.toMASShortcut()))
        XCTAssertEqual(reclaimCount, 0)

        // A WindowAction now takes chord X.
        injectWindowAction(chord(101), .leftHalf)
        mgr.reconcileNow()
        XCTAssertEqual(mgr.outcomes[x.id], .conflictWindowAction(WindowAction.leftHalf.name))
        XCTAssertEqual(monitor.unregisterCount(x.hotkey!.toMASShortcut()), 1, "X yielded")
        XCTAssertFalse(monitor.isOwned(x.hotkey!.toMASShortcut()))
        XCTAssertEqual(mgr.outcomes[y.id], .registered, "Y unaffected")
        XCTAssertEqual(reclaimCount, 1, "reclaim hook called exactly once")

        // Another reconcile must NOT call reclaim again (no new yield).
        mgr.reconcileNow()
        XCTAssertEqual(reclaimCount, 1)
    }

    // MARK: recording / app-disable register-level lifecycle

    func testRecordingUnregistersAndResumes() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let a = layout("a", chord(96))
        store.add(a)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertTrue(monitor.isOwned(a.hotkey!.toMASShortcut()))

        mgr.setRecordingForTest(true); mgr.reconcileNow()
        XCTAssertFalse(monitor.isOwned(a.hotkey!.toMASShortcut()), "chord unregistered during recording")
        XCTAssertEqual(mgr.outcomes[a.id], .suppressed)

        mgr.setRecordingForTest(false); mgr.reconcileNow()
        XCTAssertTrue(monitor.isOwned(a.hotkey!.toMASShortcut()), "re-registered after recording")
    }

    func testAppDisableUnregistersAndResumes() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let a = layout("a", chord(96))
        store.add(a)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertTrue(monitor.isOwned(a.hotkey!.toMASShortcut()))

        disabled = true; mgr.reconcileNow()
        XCTAssertFalse(monitor.isOwned(a.hotkey!.toMASShortcut()))
        disabled = false; mgr.reconcileNow()
        XCTAssertTrue(monitor.isOwned(a.hotkey!.toMASShortcut()))
    }

    /// Inactive-transition coexistence: while inactive a WindowAction takes X; on re-activation
    /// the manager must NOT re-take X.
    func testInactiveTransitionDoesNotReclaimWindowActionChord() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let x = layout("x", chord(101))
        store.add(x)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        XCTAssertTrue(monitor.isOwned(x.hotkey!.toMASShortcut()))

        mgr.setRecordingForTest(true); mgr.reconcileNow()            // inactive → X unregistered
        injectWindowAction(chord(101), .leftHalf)                   // WindowAction takes X while inactive
        mgr.setRecordingForTest(false); mgr.reconcileNow()           // active again
        XCTAssertEqual(mgr.outcomes[x.id], .conflictWindowAction(WindowAction.leftHalf.name))
        XCTAssertFalse(monitor.isOwned(x.hotkey!.toMASShortcut()), "must not re-take the WindowAction's chord")
    }

    // MARK: apply computation + fire-time guard

    func testTriggerAppliesPixelRect() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let l = CustomLayout(name: "left60", rect: NormalizedRect(x: 0, y: 0, w: 0.6, h: 1))
        store.add(l)
        let mgr = makeManager(store: store); mgr.reconcileNow()
        mgr.triggerForTest(l.id)
        let expected = NormalizedRect(x: 0, y: 0, w: 0.6, h: 1).pixelRect(in: context.target.visibleFrame)
        XCTAssertEqual(context.target.applied, expected)

        context.target.applied = nil
        mgr.triggerForTest(l.id)
        XCTAssertEqual(context.target.applied, expected, "repeated trigger idempotent")
    }

    func testFireGuardWhenDisabled() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let l = CustomLayout(name: "x", rect: NormalizedRect(x: 0, y: 0, w: 0.5, h: 1))
        store.add(l)
        let mgr = makeManager(store: store)
        disabled = true
        mgr.triggerForTest(l.id)
        XCTAssertNil(context.target.applied, "no apply while shortcuts disabled")
    }

    // MARK: reload on store change (notification path)

    func testReloadOnCustomLayoutsChanged() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let mgr = makeManager(store: store)
        mgr.start()
        defer { mgr.stop() }
        let a = layout("a", chord(96))
        store.add(a) // posts .customLayoutsChanged → debounced reconcile
        let exp = expectation(description: "reconcile")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(mgr.outcomes[a.id], .registered)
        XCTAssertTrue(monitor.isOwned(a.hotkey!.toMASShortcut()))
    }

    func testStopCancelsPendingDebouncedReconcile() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let mgr = makeManager(store: store)
        mgr.start()
        let a = layout("a", chord(96))
        store.add(a)        // posts .customLayoutsChanged → schedules an async reconcile
        mgr.stop()          // teardown BEFORE the debounce fires
        let exp = expectation(description: "pump")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertFalse(monitor.isOwned(a.hotkey!.toMASShortcut()),
                       "a pending debounced reconcile must not re-register after stop()")
    }
}
