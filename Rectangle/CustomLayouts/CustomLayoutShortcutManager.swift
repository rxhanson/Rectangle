/// CustomLayoutShortcutManager.swift
///
/// Registers global hotkeys for custom layouts on the shared MASShortcutMonitor and
/// applies the focused window's frame via the direct-AX path (bypassing WindowAction,
/// so windowHistory is never touched). Coexists with Rectangle's own ShortcutManager:
/// WindowActions always WIN — a chord a WindowAction takes is yielded and Rectangle is
/// asked to reclaim it. See docs/2026-06-23-Design-M2-Shortcut-Manager.md.

import Cocoa
import MASShortcut

extension Notification.Name {
    /// Posted after each reconcile so the M3 UI can refresh per-layout binding status.
    static let customLayoutBindingsReconciled = Notification.Name("com.perg593.chiva.customLayoutBindingsReconciled")
}

// MARK: - Injectable seams (so unit tests don't touch the real monitor / move real windows)

protocol ShortcutMonitoring {
    @discardableResult func registerChord(_ shortcut: MASShortcut, action: @escaping () -> Void) -> Bool
    func unregisterChord(_ shortcut: MASShortcut)
}

extension MASShortcutMonitor: ShortcutMonitoring {
    func registerChord(_ shortcut: MASShortcut, action: @escaping () -> Void) -> Bool {
        register(shortcut, withAction: action)        // MASShortcutMonitor's native Bool-returning API
    }
    func unregisterChord(_ shortcut: MASShortcut) {
        unregisterShortcut(shortcut)
    }
}

protocol CustomLayoutTarget {
    var visibleFrame: CGRect { get }
    func apply(_ appKitRect: CGRect)
}

protocol CustomLayoutWindowContext {
    func currentTarget() -> CustomLayoutTarget?
}

/// Real AX target: the focused window + its screen's raw visibleFrame (gap = 0).
struct AXWindowContext: CustomLayoutWindowContext {
    func currentTarget() -> CustomLayoutTarget? {
        guard let windowElement = AccessibilityElement.getFrontWindowElement(),
              let screens = ScreenDetection().detectScreens(using: windowElement) else { return nil }
        return AXTarget(windowElement: windowElement, visibleFrame: screens.currentScreen.visibleFrame)
    }

    private struct AXTarget: CustomLayoutTarget {
        let windowElement: AccessibilityElement
        let visibleFrame: CGRect
        func apply(_ appKitRect: CGRect) {
            // Direct AX frame-set, flipped to AX (top-left) coords. Never routes
            // through WindowManager/WindowAction → windowHistory is untouched.
            windowElement.setFrame(appKitRect.screenFlipped)
        }
    }
}

// MARK: - Manager

final class CustomLayoutShortcutManager {

    enum BindOutcome: Equatable {
        case registered
        case conflictWindowAction(String)   // colliding WindowAction.name
        case conflictCustomLayout(UUID)      // colliding (earlier) layout id
        case monitorRegistrationFailed
        case noHotkey
        case suppressed                      // inactive (recording / app-disabled)
    }

    /// Per-layout outcome of the last reconcile — surfaced to the M3 UI.
    private(set) var outcomes: [UUID: BindOutcome] = [:]

    private let store: CustomLayoutStore
    /// Called once when we yield a chord because a WindowAction took it, so Rectangle
    /// can reclaim it (e.g. `{ shortcutManager.reloadFromDefaults() }`).
    private let reclaim: () -> Void
    private let windowContext: CustomLayoutWindowContext
    private let conflictDefaults: UserDefaults
    private let monitor: ShortcutMonitoring
    private let isShortcutsDisabled: () -> Bool

    private var owned: [UUID: MASShortcut] = [:]
    private var suspendedForRecording = false
    private var isReconciling = false
    private var reconcileScheduled = false
    private var isStopped = false
    private var observers: [NSObjectProtocol] = []

    init(store: CustomLayoutStore,
         reclaim: @escaping () -> Void = {},
         windowContext: CustomLayoutWindowContext = AXWindowContext(),
         conflictDefaults: UserDefaults = .standard,
         monitor: ShortcutMonitoring = MASShortcutMonitor.shared(),
         isShortcutsDisabled: @escaping () -> Bool = { ApplicationToggle.shortcutsDisabled }) {
        self.store = store
        self.reclaim = reclaim
        self.windowContext = windowContext
        self.conflictDefaults = conflictDefaults
        self.monitor = monitor
        self.isShortcutsDisabled = isShortcutsDisabled
    }

    deinit { stop() }

    // MARK: Lifecycle

    func start() {
        subscribe(.customLayoutsChanged) { [weak self] _ in self?.scheduleReconcile() }
        subscribe(.changeDefaults) { [weak self] _ in self?.scheduleReconcile() }
        subscribe(UserDefaults.didChangeNotification) { [weak self] _ in self?.scheduleReconcile() }
        subscribe(.frontAppChanged) { [weak self] _ in self?.scheduleReconcile() }
        subscribe(.shortcutRecording) { [weak self] note in
            self?.suspendedForRecording = (note.object as? Bool) ?? false
            self?.scheduleReconcile()
        }
        reconcileNow()
    }

    func stop() {
        isStopped = true   // a pending debounced reconcile must not re-register after teardown
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        for (_, shortcut) in owned { monitor.unregisterChord(shortcut) }
        owned.removeAll()
    }

    private func subscribe(_ name: Notification.Name, _ block: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: block))
    }

    // MARK: Reconcile

    private func scheduleReconcile() {
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.reconcileScheduled = false
            self.reconcileNow()
        }
    }

    /// Synchronous reconcile (used by start() and tests). The single source of truth.
    func reconcileNow() {
        guard !isStopped, !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let active = !suspendedForRecording && !isShortcutsDisabled()

        // Desired registrations + outcome for EVERY layout (store order, first-wins for dups).
        // Uses the SAME conflict primitives as the M3 validator (CustomLayoutConflict) so the
        // record-time and reconcile-time classifications can't diverge.
        var desired = [UUID: MASShortcut]()
        var newOutcomes = [UUID: BindOutcome]()
        var keptLayouts = [CustomLayout]()
        for layout in store.layouts {
            guard let hotkey = layout.hotkey else { newOutcomes[layout.id] = .noHotkey; continue }
            let shortcut = hotkey.toMASShortcut()
            if !active { newOutcomes[layout.id] = .suppressed; continue }
            if let name = CustomLayoutConflict.windowActionName(for: shortcut, in: conflictDefaults) {
                newOutcomes[layout.id] = .conflictWindowAction(name); continue
            }
            // First-wins: only layouts KEPT so far this pass can be a prior duplicate.
            if let firstId = CustomLayoutConflict.customLayoutId(for: shortcut, in: keptLayouts) {
                newOutcomes[layout.id] = .conflictCustomLayout(firstId); continue
            }
            keptLayouts.append(layout)
            desired[layout.id] = shortcut
        }

        // Yield owned chords that are no longer desired (or whose chord changed).
        var yieldedDueToWindowAction = false
        for (id, shortcut) in owned {
            let stillWanted = desired[id].map { sameChord($0, shortcut) } ?? false
            if !stillWanted {
                monitor.unregisterChord(shortcut)
                owned[id] = nil
                if CustomLayoutConflict.windowActionName(for: shortcut, in: conflictDefaults) != nil {
                    yieldedDueToWindowAction = true
                }
            }
        }
        // Let Rectangle reclaim a chord we just freed because a WindowAction took it.
        if yieldedDueToWindowAction { reclaim() }

        // Register desired chords we don't already own.
        for (id, shortcut) in desired {
            if let existing = owned[id], sameChord(existing, shortcut) { newOutcomes[id] = .registered; continue }
            let ok = monitor.registerChord(shortcut) { [weak self] in self?.fire(id) }
            if ok { owned[id] = shortcut; newOutcomes[id] = .registered }
            else { newOutcomes[id] = .monitorRegistrationFailed }
        }

        outcomes = newOutcomes
        NotificationCenter.default.post(name: .customLayoutBindingsReconciled, object: nil)
    }

    private func sameChord(_ a: MASShortcut, _ b: MASShortcut) -> Bool {
        ShortcutCycle.ShortcutIdentity(a) == ShortcutCycle.ShortcutIdentity(b)
    }

    // MARK: Fire / apply

    private func fire(_ id: UUID) {
        // Belt-and-suspenders: registration-level gating already frees chords while
        // inactive, but guard the fire path too.
        guard !suspendedForRecording, !isShortcutsDisabled() else { return }
        guard let layout = store.layout(id: id), let target = windowContext.currentTarget() else { return }
        let appKitRect = layout.rect.pixelRect(in: target.visibleFrame)
        target.apply(appKitRect)
    }

    /// Test seam: fire a layout's action directly (same guards + apply path as a real keypress).
    func triggerForTest(_ id: UUID) { fire(id) }

    /// Test seam: set the recording-suspended state (mirrors the .shortcutRecording handler)
    /// without notification/runloop timing, for deterministic tests.
    func setRecordingForTest(_ recording: Bool) { suspendedForRecording = recording }
}
