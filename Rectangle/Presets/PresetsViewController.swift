import Cocoa
import MASShortcut

class PresetsViewController: NSViewController {

    // MARK: - Subviews

    private var monitorView: MonitorVisualizationView!
    private var screenInfoLabel: NSTextField!
    private var presetsTableView: NSTableView!
    private var windowStatesTableView: NSTableView!

    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var restoreButton: NSButton!
    private var refreshAllButton: NSButton!
    private var removeAppButton: NSButton!
    private var addAppButton: NSButton!
    private var editAppButton: NSButton!

    private var shortcutView: MASShortcutView!
    private var capturedForLabel: NSTextField!

    // MARK: - State

    private var selectedPresetIndex: Int = -1
    private var observers: [NSObjectProtocol] = []

    private var manager: PresetManager { .shared }

    private var selectedPreset: ScreenPreset? {
        let i = selectedPresetIndex
        guard i >= 0, i < manager.presets.count else { return nil }
        return manager.presets[i]
    }

    private var sortedStates: [AppWindowState] {
        guard let p = selectedPreset else { return [] }
        return p.windowStates.sorted {
            if $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedSame {
                return $0.windowIndex < $1.windowIndex
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    private func displayName(for state: AppWindowState) -> String {
        guard let p = selectedPreset else { return state.appName }
        let sameBundle = p.windowStates.filter { $0.bundleId == state.bundleId }
            .sorted { $0.windowIndex < $1.windowIndex }
        guard sameBundle.count > 1, let pos = sameBundle.firstIndex(where: { $0.id == state.id }) else {
            return state.appName
        }
        return "\(state.appName) (\(pos + 1))"
    }

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadUI()
        setupObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - UI construction

    private func buildUI() {
        let p: CGFloat = 16

        // Monitor visualization
        let monLabel = boldLabel("Connected Displays")
        monitorView = MonitorVisualizationView(frame: .zero)
        monitorView.wantsLayer = true
        monitorView.layer?.cornerRadius = 8
        screenInfoLabel = smallLabel("")

        let sep1 = separator()

        // Presets list (full width)
        let preLabel = boldLabel("Presets")
        presetsTableView = makeTableView(columns: [
            ("name", "Name", 220),
            ("shortcut", "Shortcut", 140),
        ], rowHeight: 22)
        presetsTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        presetsTableView.target = self
        presetsTableView.doubleAction = #selector(presetsTableDoubleClick(_:))
        let presetsScroll = inScrollView(presetsTableView)

        addButton = NSButton(title: "+", target: self, action: #selector(addPreset))
        addButton.bezelStyle = .smallSquare
        removeButton = NSButton(title: "−", target: self, action: #selector(removePreset))
        removeButton.bezelStyle = .smallSquare
        restoreButton = NSButton(title: "Restore Now", target: self, action: #selector(restoreNow))
        restoreButton.bezelStyle = .rounded

        shortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        shortcutView.translatesAutoresizingMaskIntoConstraints = false
        shortcutView.shortcutValueChange = { [weak self] _ in
            self?.presetsTableView.reloadData()
        }

        let presetButtons = row([addButton, removeButton, restoreButton, shortcutView])

        capturedForLabel = smallLabel("")
        capturedForLabel.font = .systemFont(ofSize: 11, weight: .medium)

        let sep2 = separator()

        // App window states
        let stateLabel = boldLabel("App Windows in Preset")
        windowStatesTableView = makeTableView(columns: [
            ("app", "App / Window", 220),
            ("screen", "Display", 110),
            ("frame", "Frame (x, y, w×h)", 240),
        ], rowHeight: 20)
        windowStatesTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let statesScroll = inScrollView(windowStatesTableView)

        addAppButton = NSButton(title: "Add App…", target: self, action: #selector(showAddAppPicker(_:)))
        addAppButton.bezelStyle = .rounded
        editAppButton = NSButton(title: "Edit App…", target: self, action: #selector(showEditAppMenu(_:)))
        editAppButton.bezelStyle = .rounded
        refreshAllButton = NSButton(title: "Refresh All Positions", target: self, action: #selector(refreshAllPositions))
        refreshAllButton.bezelStyle = .rounded
        removeAppButton = NSButton(title: "Remove App", target: self, action: #selector(removeApp))
        removeAppButton.bezelStyle = .rounded
        let stateButtons = row([addAppButton, editAppButton, refreshAllButton, removeAppButton])

        // Add all views
        let subviews: [NSView] = [
            monLabel, monitorView, screenInfoLabel,
            sep1, preLabel, presetsScroll, presetButtons,
            capturedForLabel, sep2,
            stateLabel, statesScroll, stateButtons
        ]
        subviews.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let statesHeight = statesScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        statesHeight.priority = .defaultHigh

        // Layout
        NSLayoutConstraint.activate([
            // Min content size — forces the tab/window to grow
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 720),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 580),

            // Monitor section
            monLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: p),
            monLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),

            monitorView.topAnchor.constraint(equalTo: monLabel.bottomAnchor, constant: 6),
            monitorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            monitorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),
            monitorView.heightAnchor.constraint(equalToConstant: 70),

            screenInfoLabel.topAnchor.constraint(equalTo: monitorView.bottomAnchor, constant: 4),
            screenInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            screenInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),

            sep1.topAnchor.constraint(equalTo: screenInfoLabel.bottomAnchor, constant: 8),
            sep1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            sep1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),
            sep1.heightAnchor.constraint(equalToConstant: 1),

            // Presets table (full width)
            preLabel.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 8),
            preLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),

            presetsScroll.topAnchor.constraint(equalTo: preLabel.bottomAnchor, constant: 4),
            presetsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            presetsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),
            presetsScroll.heightAnchor.constraint(equalToConstant: 110),

            presetButtons.topAnchor.constraint(equalTo: presetsScroll.bottomAnchor, constant: 6),
            presetButtons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),

            capturedForLabel.topAnchor.constraint(equalTo: presetButtons.bottomAnchor, constant: 6),
            capturedForLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),

            // Sep2
            sep2.topAnchor.constraint(equalTo: capturedForLabel.bottomAnchor, constant: 10),
            sep2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            sep2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),
            sep2.heightAnchor.constraint(equalToConstant: 1),

            // App states
            stateLabel.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 8),
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),

            statesScroll.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 4),
            statesScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            statesScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),
            statesScroll.bottomAnchor.constraint(equalTo: stateButtons.topAnchor, constant: -6),
            statesHeight,

            stateButtons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            stateButtons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -p),

            // Detail inner constraints
            shortcutView.widthAnchor.constraint(equalToConstant: 180),
            shortcutView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    // MARK: - Helpers

    private func boldLabel(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .boldSystemFont(ofSize: 12)
        return t
    }

    private func smallLabel(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .secondaryLabelColor
        return t
    }

    private func separator() -> NSBox {
        let b = NSBox(); b.boxType = .separator; return b
    }

    private func inScrollView(_ tv: NSTableView) -> NSScrollView {
        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder
        return sv
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 6
        s.alignment = .centerY
        return s
    }

    private func shortcutText(for preset: ScreenPreset) -> String {
        guard let key = preset.shortcutDefaultsKey,
              let data = UserDefaults.standard.object(forKey: key) else { return "—" }
        let transformer = ValueTransformer(forName: NSValueTransformerName(MASDictionaryTransformerName))
        guard let shortcut = transformer?.reverseTransformedValue(data) as? MASShortcut else { return "—" }
        return shortcut.modifierFlagsString + (shortcut.keyCodeString ?? "")
    }

    private func makeTableView(columns: [(String, String, CGFloat)], rowHeight: CGFloat) -> NSTableView {
        let tv = NSTableView()
        tv.delegate = self
        tv.dataSource = self
        tv.rowHeight = rowHeight
        tv.usesAlternatingRowBackgroundColors = true
        tv.allowsEmptySelection = true
        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            tv.addTableColumn(col)
        }
        return tv
    }

    // MARK: - Data reload

    private func reloadUI() {
        presetsTableView.reloadData()
        refreshDetail()
        windowStatesTableView.reloadData()
        refreshMonitorSection()
        updateButtons()
    }

    private func refreshMonitorSection() {
        monitorView.refresh()
        let screens = PresetManager.orderedScreens()
        let parts = screens.enumerated().map { i, s in
            let res = "\(Int(s.frame.width))×\(Int(s.frame.height))"
            return i == 0 ? "Primary Display: \(s.localizedName) (\(res))" : "Secondary Display \(i): \(s.localizedName) (\(res))"
        }
        screenInfoLabel.stringValue = parts.joined(separator: "   |   ")
    }

    private func refreshDetail() {
        guard let preset = selectedPreset else {
            capturedForLabel.stringValue = ""
            shortcutView.isEnabled = false
            shortcutView.associatedUserDefaultsKey = nil
            return
        }

        let windowCount = preset.windowStates.count
        let uniqueApps = Set(preset.windowStates.map { $0.bundleId }).count
        let displayWord = preset.screenCount == 1 ? "display" : "displays"
        let winWord = windowCount == 1 ? "window" : "windows"
        let appWord = uniqueApps == 1 ? "app" : "apps"
        capturedForLabel.stringValue = "Captured for \(preset.screenCount) \(displayWord) · \(windowCount) \(winWord) across \(uniqueApps) \(appWord)"

        let key: String
        if let existing = preset.shortcutDefaultsKey {
            key = existing
        } else {
            key = manager.assignShortcut(presetId: preset.id) ?? "preset_restore_\(preset.id)"
        }
        shortcutView.isEnabled = true
        shortcutView.setAssociatedUserDefaultsKey(key, withTransformerName: MASDictionaryTransformerName)
    }

    private func updateButtons() {
        let hasSel = selectedPreset != nil
        removeButton.isEnabled = hasSel
        restoreButton.isEnabled = hasSel
        addAppButton.isEnabled = hasSel
        let hasApps = hasSel && !sortedStates.isEmpty
        refreshAllButton.isEnabled = hasApps
        let hasAppSel = hasSel && windowStatesTableView.selectedRow >= 0
        removeAppButton.isEnabled = hasAppSel
        editAppButton.isEnabled = hasAppSel
    }

    // MARK: - Notifications

    private func setupObservers() {
        observers.append(Notification.Name.presetsChanged.onPost { [weak self] _ in
            DispatchQueue.main.async { self?.reloadUI() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshMonitorSection() })
    }

    // MARK: - Actions

    @objc private func addPreset() {
        let existingNames = Set(manager.presets.map { $0.name })
        var n = 1
        while existingNames.contains("Preset \(n)") { n += 1 }
        guard let preset = manager.saveCurrentLayout(name: "Preset \(n)") else {
            let a = NSAlert()
            if !AXIsProcessTrusted() {
                a.messageText = "Accessibility permission required"
                a.informativeText = "Rectangle needs Accessibility permission to read other apps' window positions.\n\nOpen System Settings → Privacy & Security → Accessibility and enable Rectangle (this debug build may need to be added separately from the App Store build)."
                a.addButton(withTitle: "Open System Settings")
                a.addButton(withTitle: "Cancel")
                if a.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            } else {
                a.messageText = "No windows found"
                a.informativeText = "No running apps currently expose a window via Accessibility. Open some apps with visible windows and try again."
                a.runModal()
            }
            return
        }
        if let row = manager.presets.firstIndex(where: { $0.id == preset.id }) {
            selectedPresetIndex = row
            presetsTableView.reloadData()
            presetsTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            refreshDetail()
            windowStatesTableView.reloadData()
            updateButtons()
            DispatchQueue.main.async {
                self.presetsTableView.editColumn(0, row: row, with: nil, select: true)
            }
        }
    }

    @objc private func removePreset() {
        guard let preset = selectedPreset else { return }
        let a = NSAlert()
        a.messageText = "Delete \"\(preset.name)\"?"
        a.informativeText = "The preset and its keyboard shortcut will be permanently removed."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        selectedPresetIndex = -1
        manager.deletePreset(id: preset.id)
    }

    @objc private func restoreNow() {
        guard let preset = selectedPreset else { return }
        manager.restorePreset(preset)
    }

    @objc private func presetNameCellEdited(_ sender: NSTextField) {
        let row = sender.tag
        guard row >= 0, row < manager.presets.count else { return }
        let name = sender.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            sender.stringValue = manager.presets[row].name
            return
        }
        manager.renamePreset(id: manager.presets[row].id, newName: name)
    }

    @objc private func presetsTableDoubleClick(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < manager.presets.count else { return }
        sender.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func refreshAllPositions() {
        guard let preset = selectedPreset else { return }
        var missing: [String] = []
        for state in sortedStates {
            guard let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == state.bundleId })
            else {
                missing.append(displayName(for: state))
                continue
            }
            let windows = PresetManager.cgWindows(forPID: app.processIdentifier)
            let idx = state.windowIndex < windows.count ? state.windowIndex : 0
            guard idx < windows.count else {
                missing.append(displayName(for: state))
                continue
            }
            manager.updateWindowState(presetId: preset.id, stateId: state.id, newFrame: windows[idx].frame)
        }
        if !missing.isEmpty {
            let a = NSAlert()
            a.messageText = "Couldn't refresh \(missing.count) window\(missing.count == 1 ? "" : "s")"
            a.informativeText = "Not running or no window frame returned:\n\n" + missing.joined(separator: ", ")
            a.runModal()
        }
    }

    @objc private func setToCurrent() {
        guard let preset = selectedPreset else { return }
        let row = windowStatesTableView.selectedRow
        guard row >= 0, row < sortedStates.count else { return }
        let state = sortedStates[row]
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == state.bundleId })
        else {
            let a = NSAlert()
            a.messageText = "\(state.appName) is not running"
            a.informativeText = "Launch \(state.appName) and try again."
            a.runModal()
            return
        }
        let windows = PresetManager.cgWindows(forPID: app.processIdentifier)
        let idx = state.windowIndex < windows.count ? state.windowIndex : 0
        guard idx < windows.count else {
            let a = NSAlert()
            a.messageText = "Couldn't read window bounds"
            a.informativeText = "\(state.appName) didn't return a usable window frame."
            a.runModal()
            return
        }
        manager.updateWindowState(presetId: preset.id, stateId: state.id, newFrame: windows[idx].frame)
    }

    @objc private func removeApp() {
        guard let preset = selectedPreset else { return }
        let row = windowStatesTableView.selectedRow
        guard row >= 0, row < sortedStates.count else { return }
        manager.removeWindowState(presetId: preset.id, stateId: sortedStates[row].id)
    }

    @objc private func showEditAppMenu(_ sender: NSButton) {
        guard let preset = selectedPreset else { return }
        let row = windowStatesTableView.selectedRow
        guard row >= 0, row < sortedStates.count else { return }
        let state = sortedStates[row]

        let menu = NSMenu()

        let updateItem = NSMenuItem(title: "Update Position to Current", action: #selector(setToCurrent), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let moveItem = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let count = max(preset.screenCount, 1)
        for i in 0..<count {
            let label = i == 0 ? "Primary Display" : "Secondary Display \(i)"
            let item = NSMenuItem(title: label, action: #selector(applyScreenChange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = i
            item.state = (i == state.screenIndex) ? .on : .off
            submenu.addItem(item)
        }
        moveItem.submenu = submenu
        menu.addItem(moveItem)

        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func applyScreenChange(_ sender: NSMenuItem) {
        guard let preset = selectedPreset,
              let newIndex = sender.representedObject as? Int else { return }
        let row = windowStatesTableView.selectedRow
        guard row >= 0, row < sortedStates.count else { return }
        manager.changeAppScreen(presetId: preset.id, stateId: sortedStates[row].id, newScreenIndex: newIndex)
    }

    @objc private func showAddAppPicker(_ sender: NSButton) {
        guard selectedPreset != nil else { return }
        let picker = AddAppPickerViewController()
        picker.onPick = { [weak self, weak picker] app in
            picker?.view.window?.close()
            self?.handlePickedApp(app)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = picker
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func handlePickedApp(_ installedApp: InstalledApp) {
        guard let preset = selectedPreset else { return }

        if let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == installedApp.bundleId }) {
            let windows = PresetManager.cgWindows(forPID: app.processIdentifier)
            if windows.count == 1 {
                manager.addWindowToPreset(
                    presetId: preset.id, bundleId: installedApp.bundleId,
                    appName: installedApp.name,
                    frame: windows[0].frame, windowTitle: windows[0].title)
                return
            } else if windows.count > 1 {
                showWindowPickerMenu(bundleId: installedApp.bundleId,
                                    appName: installedApp.name, windows: windows)
                return
            }
        }

        // Not running or no visible window: launch and capture when a window appears.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: installedApp.url, configuration: config) { [weak self] app, _ in
            guard let self = self, let app = app else { return }
            self.waitForFirstWindow(pid: app.processIdentifier, retriesLeft: 30) { frame, title in
                guard let frame = frame else { return }
                self.manager.addWindowToPreset(
                    presetId: preset.id, bundleId: installedApp.bundleId,
                    appName: installedApp.name, frame: frame, windowTitle: title)
            }
        }
    }

    private func waitForFirstWindow(pid: pid_t, retriesLeft: Int,
                                    completion: @escaping (CGRect?, String?) -> Void) {
        let windows = PresetManager.cgWindows(forPID: pid)
        if let first = windows.first {
            DispatchQueue.main.async { completion(first.frame, first.title) }
            return
        }
        guard retriesLeft > 0 else {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForFirstWindow(pid: pid, retriesLeft: retriesLeft - 1, completion: completion)
        }
    }

    private func showWindowPickerMenu(bundleId: String, appName: String,
                                      windows: [(frame: CGRect, title: String?)]) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Pick a window", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for (i, w) in windows.enumerated() {
            let label = w.title ?? "Window \(i + 1)"
            let item = NSMenuItem(title: label, action: #selector(addWindowFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = AddWindowPayload(
                bundleId: bundleId, appName: appName, frame: w.frame, title: w.title)
            menu.addItem(item)
        }
        let origin = NSPoint(x: 0, y: addAppButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: addAppButton)
    }

    private struct AddWindowPayload {
        let bundleId: String
        let appName: String
        let frame: CGRect
        let title: String?
    }

    @objc private func addWindowFromMenu(_ sender: NSMenuItem) {
        guard let preset = selectedPreset,
              let payload = sender.representedObject as? AddWindowPayload else { return }
        manager.addWindowToPreset(
            presetId: preset.id,
            bundleId: payload.bundleId,
            appName: payload.appName,
            frame: payload.frame,
            windowTitle: payload.title
        )
    }

    /// Resolve the frontmost on-screen window frame for a given PID.
    /// Prefers CGWindowList (no AX required); falls back to AX if CG doesn't return usable bounds.
    private func frontWindowFrame(forPID pid: pid_t) -> CGRect? {
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let infoList = (CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]]) ?? []
        let candidates = infoList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
            ($0[kCGWindowLayer as String] as? Int) == 0
        }
        for info in candidates {
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict),
                  rect.width > 0, rect.height > 0 else { continue }
            return rect
        }

        // AX fallback
        let el = AccessibilityElement(pid)
        if let win = el.windowElements?.first {
            let f = win.frame
            if !f.isNull, f.width > 0, f.height > 0 { return f }
        }
        return nil
    }
}

// MARK: - NSTableViewDataSource

extension PresetsViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === presetsTableView ? manager.presets.count : sortedStates.count
    }
}

// MARK: - NSTableViewDelegate

extension PresetsViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let colId = tableColumn?.identifier.rawValue ?? ""
        if tableView === presetsTableView {
            guard row < manager.presets.count else { return nil }
            let preset = manager.presets[row]
            if colId == "shortcut" {
                return textCell(for: tableView, identifier: colId, text: shortcutText(for: preset))
            }
            let cell = textCell(for: tableView, identifier: colId, text: preset.name)
            if let tf = cell.textField {
                tf.isEditable = true
                tf.isSelectable = true
                tf.isBordered = false
                tf.drawsBackground = false
                tf.focusRingType = .none
                tf.target = self
                tf.action = #selector(presetNameCellEdited(_:))
                tf.cell?.sendsActionOnEndEditing = true
                tf.tag = row
            }
            return cell
        } else {
            guard row < sortedStates.count else { return nil }
            let state = sortedStates[row]
            let text: String
            switch colId {
            case "app":    text = displayName(for: state)
            case "screen": text = state.screenIndex == 0 ? "Primary" : "Secondary \(state.screenIndex)"
            case "frame":
                let f = state.frame
                text = String(format: "%.0f, %.0f  %.0f×%.0f", f.x, f.y, f.width, f.height)
            default: return nil
            }
            return textCell(for: tableView, identifier: colId, text: text)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        if tv === presetsTableView {
            let r = presetsTableView.selectedRow
            selectedPresetIndex = r >= 0 ? r : -1
            refreshDetail()
            windowStatesTableView.reloadData()
        }
        updateButtons()
    }

    private func textCell(for tableView: NSTableView, identifier: String, text: String) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = id
        let tf = NSTextField(labelWithString: text)
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - Installed-app picker popover

class AddAppPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onPick: ((InstalledApp) -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var allApps: [InstalledApp] = []
    private var filtered: [InstalledApp] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 440))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        allApps = PresetManager.allInstalledApps()
        filtered = allApps

        searchField.placeholderString = "Search apps"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col.title = "App"
        col.width = 340
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    @objc private func searchChanged() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            filtered = allApps
        } else {
            filtered = allApps.filter { $0.name.range(of: q, options: .caseInsensitive) != nil }
        }
        tableView.reloadData()
    }

    @objc private func rowClicked() {
        let r = tableView.clickedRow
        guard r >= 0, r < filtered.count else { return }
        onPick?(filtered[r])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count else { return nil }
        let app = filtered[row]

        let cell = NSTableCellView()
        let imageView = NSImageView()
        imageView.image = app.icon
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(labelWithString: app.name)
        nameField.font = .systemFont(ofSize: 12)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let statusDot = NSTextField(labelWithString: app.isRunning ? "●" : "")
        statusDot.font = .systemFont(ofSize: 9)
        statusDot.textColor = .systemGreen
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(nameField)
        cell.addSubview(statusDot)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            nameField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: statusDot.leadingAnchor, constant: -8),

            statusDot.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            statusDot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
