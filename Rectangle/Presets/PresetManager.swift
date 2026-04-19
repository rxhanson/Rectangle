import Cocoa
import MASShortcut
import os.log

private let presetLog = OSLog(subsystem: "com.knollsoft.Rectangle", category: "presets")

class PresetManager {
    static let shared = PresetManager()

    private(set) var presets: [ScreenPreset] = []
    private let defaultsKey = "screenPresets"

    private init() { load() }

    // MARK: - Screen helpers

    /// The system's primary display — the one with the menu bar in System Settings.
    /// This is the screen at origin (0, 0), NOT `NSScreen.main` (which follows keyboard focus).
    static func primaryScreen() -> NSScreen? {
        return NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
    }

    static func orderedScreens() -> [NSScreen] {
        var screens = NSScreen.screens
        guard let primary = primaryScreen() else { return screens }
        screens.removeAll { $0 == primary }
        screens.sort { $0.frame.minX < $1.frame.minX }
        return [primary] + screens
    }

    // Convert NSScreen frame to AX coordinate space (origin = top-left of primary screen, y↓)
    static func axFrame(for screen: NSScreen) -> CGRect {
        guard let primary = primaryScreen() else { return screen.frame }
        let totalHeight = primary.frame.height
        let axY = totalHeight - screen.frame.maxY
        return CGRect(x: screen.frame.minX, y: axY, width: screen.frame.width, height: screen.frame.height)
    }

    static func screenIndex(forAXPoint point: CGPoint) -> Int {
        let screens = orderedScreens()
        for (i, screen) in screens.enumerated() {
            if axFrame(for: screen).contains(point) { return i }
        }
        return 0
    }

    // Convert an absolute AX frame on a given screen into a 0–1 fraction relative to that screen.
    static func relativeFrame(forAX frame: CGRect, onScreenIndex idx: Int) -> CGRect? {
        let screens = orderedScreens()
        guard idx >= 0, idx < screens.count else { return nil }
        let s = axFrame(for: screens[idx])
        guard s.width > 0, s.height > 0 else { return nil }
        return CGRect(
            x: (frame.minX - s.minX) / s.width,
            y: (frame.minY - s.minY) / s.height,
            width: frame.width / s.width,
            height: frame.height / s.height
        )
    }

    // Convert a 0–1 relative frame back to an absolute AX frame on the current screen at `idx`.
    static func absoluteFrame(fromRelative rel: CGRect, onScreenIndex idx: Int) -> CGRect? {
        let screens = orderedScreens()
        guard idx >= 0, idx < screens.count else { return nil }
        let s = axFrame(for: screens[idx])
        return CGRect(
            x: s.minX + rel.minX * s.width,
            y: s.minY + rel.minY * s.height,
            width: rel.width * s.width,
            height: rel.height * s.height
        )
    }

    private static func makeWindowState(bundleId: String, appName: String, frame: CGRect,
                                        windowIndex: Int = 0, windowTitle: String? = nil,
                                        id: String? = nil) -> AppWindowState {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let idx = screenIndex(forAXPoint: center)
        let rel = relativeFrame(forAX: frame, onScreenIndex: idx).map(CodableCGRect.init)
        return AppWindowState(
            id: id ?? UUID().uuidString,
            bundleId: bundleId,
            appName: appName,
            screenIndex: idx,
            frame: CodableCGRect(frame),
            relativeFrame: rel,
            windowIndex: windowIndex,
            windowTitle: windowTitle
        )
    }

    /// Snapshot of windows owned by a PID that are currently user-visible.
    /// AX is the source of truth, restricted to `AXStandardWindow` subrole; the window must also
    /// appear in CG's on-screen, layer-0, alpha>0, ≥100×100 list.
    static func cgWindows(forPID pid: pid_t) -> [(frame: CGRect, title: String?)] {
        // Visible CG rects and their titles, for matching.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        var visibleCG: [(frame: CGRect, title: String?)] = []
        if let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int32, ownerPid == pid,
                      let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                      let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: boundsDict),
                      rect.width >= 100, rect.height >= 100 else { continue }
                let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
                visibleCG.append((frame: rect, title: title))
            }
        }
        guard !visibleCG.isEmpty else { return [] }

        // Prefer AX for enumeration; only keep standard windows backed by a visible CG rect.
        let el = AccessibilityElement(pid)
        guard let wins = el.windowElements, !wins.isEmpty else {
            return visibleCG
        }

        var remaining = visibleCG
        var results: [(frame: CGRect, title: String?)] = []
        for win in wins {
            // Skip sheets, popovers, tooltips, drawers, floating panels, etc.
            if let sub = win.subrole, sub != .standardWindow { continue }
            let f = win.frame
            guard !f.isNull, f.width >= 100, f.height >= 100 else { continue }
            guard let nearestIdx = remaining.enumerated().min(by: { a, b in
                let d1 = hypot(a.element.frame.origin.x - f.origin.x, a.element.frame.origin.y - f.origin.y)
                let d2 = hypot(b.element.frame.origin.x - f.origin.x, b.element.frame.origin.y - f.origin.y)
                return d1 < d2
            })?.offset else { break }
            let match = remaining[nearestIdx]
            let dist = hypot(match.frame.origin.x - f.origin.x, match.frame.origin.y - f.origin.y)
            guard dist < 50 else { continue }
            results.append((frame: f, title: match.title))
            remaining.remove(at: nearestIdx)
        }
        return results
    }

    // MARK: - Save

    func saveCurrentLayout(name: String) -> ScreenPreset? {
        let screens = PresetManager.orderedScreens()
        var states = [AppWindowState]()

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            let windows = PresetManager.cgWindows(forPID: app.processIdentifier)
            for (i, w) in windows.enumerated() {
                states.append(PresetManager.makeWindowState(
                    bundleId: bundleId,
                    appName: app.localizedName ?? bundleId,
                    frame: w.frame,
                    windowIndex: i,
                    windowTitle: w.title
                ))
            }
        }

        guard !states.isEmpty else { return nil }

        let preset = ScreenPreset(name: name, screenCount: screens.count, windowStates: states)
        presets.append(preset)
        persist()
        Notification.Name.presetsChanged.post()
        return preset
    }

    // MARK: - Restore

    func restorePreset(_ preset: ScreenPreset) {
        os_log("restorePreset '%{public}@' screenCount=%{public}d states=%{public}d axTrusted=%{public}d",
               log: presetLog, type: .info,
               preset.name, preset.screenCount, preset.windowStates.count, AXIsProcessTrusted() ? 1 : 0)
        let currentScreens = PresetManager.orderedScreens()
        guard preset.screenCount <= currentScreens.count else {
            os_log("  screen count mismatch, aborting", log: presetLog, type: .info)
            NSSound.beep()
            return
        }

        // Group by bundleId, preserving the order rows were added to the preset
        // (important so newly-added windows don't fight over windowIndex=0).
        var grouped: [String: [AppWindowState]] = [:]
        for state in preset.windowStates {
            grouped[state.bundleId, default: []].append(state)
        }

        var uninstalled: [String] = []

        for (bundleId, states) in grouped {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                uninstalled.append(bundleId)
                continue
            }

            let targets: [CGRect] = states.map { s in
                if let rel = s.relativeFrame?.cgRect,
                   let abs = PresetManager.absoluteFrame(fromRelative: rel, onScreenIndex: s.screenIndex) {
                    return abs
                }
                return s.frame.cgRect
            }

            if let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleId }) {
                applyFrames(to: app, states: states, targets: targets)
            } else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] app, _ in
                    guard let self = self, let app = app else { return }
                    DispatchQueue.main.async {
                        self.waitForWindowsAndApplyFrames(app: app, states: states, targets: targets, retriesLeft: 30)
                    }
                }
            }
        }

        if !uninstalled.isEmpty, let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i].windowStates.removeAll { uninstalled.contains($0.bundleId) }
            persist()
            Notification.Name.presetsChanged.post()
        }
    }

    private func applyFrames(to app: NSRunningApplication, states: [AppWindowState], targets: [CGRect]) {
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        let el = AccessibilityElement(app.processIdentifier)
        let liveWindows = el.windowElements ?? []
        os_log("applyFrames %{public}@ liveAXCount=%{public}d storedCount=%{public}d",
               log: presetLog, type: .info, name, liveWindows.count, states.count)

        // Map each stored state to a live window in order. If we run out of live windows, stop.
        for (i, state) in states.enumerated() {
            guard i < liveWindows.count else {
                os_log("  skip: only %{public}d live windows for '%{public}@'",
                       log: presetLog, type: .info, liveWindows.count, state.appName)
                break
            }
            let win = liveWindows[i]
            os_log("  [%{public}d] '%{public}@' screenIdx=%{public}d rel=%{public}@ target=%{public}@ before=%{public}@",
                   log: presetLog, type: .info,
                   i, state.windowTitle ?? "?",
                   state.screenIndex,
                   state.relativeFrame.map { NSStringFromRect($0.cgRect) } ?? "nil",
                   NSStringFromRect(targets[i]),
                   NSStringFromRect(win.frame))
            win.setFrame(targets[i])
            os_log("  [%{public}d] after=%{public}@",
                   log: presetLog, type: .info, i, NSStringFromRect(win.frame))
        }
    }

    private func waitForWindowsAndApplyFrames(app: NSRunningApplication,
                                              states: [AppWindowState],
                                              targets: [CGRect],
                                              retriesLeft: Int) {
        if app.isTerminated { return }
        let el = AccessibilityElement(app.processIdentifier)
        let liveCount = el.windowElements?.count ?? 0
        if liveCount >= states.count || liveCount > 0 && retriesLeft == 0 {
            applyFrames(to: app, states: states, targets: targets)
            return
        }
        guard retriesLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForWindowsAndApplyFrames(app: app, states: states, targets: targets, retriesLeft: retriesLeft - 1)
        }
    }

    func restorePresetForCurrentScreenCount() {
        let count = NSScreen.screens.count
        // Prefer an exact match; fall back to the largest preset that still fits the current setup.
        let exact = presets.first { $0.screenCount == count }
        let fallback = presets
            .filter { $0.screenCount <= count }
            .max(by: { $0.screenCount < $1.screenCount })
        guard let preset = exact ?? fallback else {
            NSSound.beep()
            return
        }
        restorePreset(preset)
    }

    // MARK: - CRUD

    func renamePreset(id: String, newName: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = newName
        persist()
        Notification.Name.presetsChanged.post()
    }

    func deletePreset(id: String) {
        if let preset = presets.first(where: { $0.id == id }),
           let key = preset.shortcutDefaultsKey {
            MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        presets.removeAll { $0.id == id }
        persist()
        Notification.Name.presetsChanged.post()
    }

    /// Enumerate installed apps in standard macOS application directories.
    static func allInstalledApps() -> [InstalledApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            home.appendingPathComponent("Applications").path
        ]
        var seenBundleIds = Set<String>()
        var apps: [InstalledApp] = []
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = "\(dir)/\(entry)"
                let url = URL(fileURLWithPath: path)
                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier,
                      seenBundleIds.insert(bid).inserted else { continue }
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? String(entry.dropLast(4))
                let icon = NSWorkspace.shared.icon(forFile: path)
                apps.append(InstalledApp(
                    url: url, bundleId: bid, name: name, icon: icon,
                    isRunning: running.contains(bid)))
            }
        }
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }

    /// Add a single captured window to a preset.
    func addWindowToPreset(presetId: String, bundleId: String, appName: String,
                           frame: CGRect, windowTitle: String?) {
        guard let i = presets.firstIndex(where: { $0.id == presetId }) else { return }
        let existingForBundle = presets[i].windowStates.filter { $0.bundleId == bundleId }.count
        presets[i].windowStates.append(PresetManager.makeWindowState(
            bundleId: bundleId,
            appName: appName,
            frame: frame,
            windowIndex: existingForBundle,
            windowTitle: windowTitle
        ))
        persist()
        Notification.Name.presetsChanged.post()
    }

    func updateWindowState(presetId: String, stateId: String, newFrame: CGRect) {
        guard let i = presets.firstIndex(where: { $0.id == presetId }),
              let j = presets[i].windowStates.firstIndex(where: { $0.id == stateId }) else { return }
        let old = presets[i].windowStates[j]
        presets[i].windowStates[j] = PresetManager.makeWindowState(
            bundleId: old.bundleId, appName: old.appName, frame: newFrame,
            windowIndex: old.windowIndex, windowTitle: old.windowTitle, id: old.id)
        persist()
        Notification.Name.presetsChanged.post()
    }

    func changeAppScreen(presetId: String, stateId: String, newScreenIndex: Int) {
        guard let i = presets.firstIndex(where: { $0.id == presetId }),
              let j = presets[i].windowStates.firstIndex(where: { $0.id == stateId }) else { return }
        let old = presets[i].windowStates[j]
        let rel = old.relativeFrame?.cgRect
            ?? CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let absFrame = PresetManager.absoluteFrame(fromRelative: rel, onScreenIndex: newScreenIndex)
            ?? old.frame.cgRect
        presets[i].windowStates[j] = AppWindowState(
            id: old.id,
            bundleId: old.bundleId,
            appName: old.appName,
            screenIndex: newScreenIndex,
            frame: CodableCGRect(absFrame),
            relativeFrame: CodableCGRect(rel),
            windowIndex: old.windowIndex,
            windowTitle: old.windowTitle
        )
        persist()
        Notification.Name.presetsChanged.post()
    }

    func removeWindowState(presetId: String, stateId: String) {
        guard let i = presets.firstIndex(where: { $0.id == presetId }) else { return }
        presets[i].windowStates.removeAll { $0.id == stateId }
        persist()
        Notification.Name.presetsChanged.post()
    }

    // MARK: - Shortcuts

    func registerAllShortcuts() {
        for preset in presets {
            guard let key = preset.shortcutDefaultsKey else { continue }
            bindShortcut(for: preset, key: key)
        }
    }

    func assignShortcut(presetId: String) -> String? {
        guard let i = presets.firstIndex(where: { $0.id == presetId }) else { return nil }
        let key = "preset_restore_\(presetId)"
        presets[i].shortcutDefaultsKey = key
        persist()
        bindShortcut(for: presets[i], key: key)
        return key
    }

    func removeShortcut(presetId: String) {
        guard let i = presets.firstIndex(where: { $0.id == presetId }),
              let key = presets[i].shortcutDefaultsKey else { return }
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        presets[i].shortcutDefaultsKey = nil
        persist()
    }

    private func bindShortcut(for preset: ScreenPreset, key: String) {
        let presetId = preset.id
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: key, toAction: {
            guard let p = PresetManager.shared.presets.first(where: { $0.id == presetId }) else { return }
            PresetManager.shared.restorePreset(p)
        })
    }

    // MARK: - Persistence

    func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(presets),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: defaultsKey)
    }

    private func load() {
        guard let json = UserDefaults.standard.string(forKey: defaultsKey),
              let data = json.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        presets = (try? decoder.decode([ScreenPreset].self, from: data)) ?? []
    }
}
