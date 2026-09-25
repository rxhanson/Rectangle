import Cocoa

/// Resetting a saved limit never resizes its window.
final class WindowSizeLimitsWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Row {
        let record: WindowSizeLimitRecord
        init(_ record: WindowSizeLimitRecord) { self.record = record }
    }
    private final class Group {
        let bundleID: String
        let name: String
        let windows: [Row]
        init(bundleID: String, name: String, windows: [WindowSizeLimitRecord]) {
            self.bundleID = bundleID; self.name = name; self.windows = windows.map(Row.init)
        }
    }
    private var groups: [Group] = []
    private var displayedRecords: [WindowSizeLimitRecord]?
    private var displayedRememberState: Bool?
    private let outline = NSOutlineView()
    private let resetWindow = NSButton(title: "Reset Window".localized, target: nil, action: nil)
    private let resetApp = NSButton(title: "Reset Application".localized, target: nil, action: nil)
    private let resetAll = NSButton(title: "Reset All".localized, target: nil, action: nil)
    private var observer: NSObjectProtocol?
    private var refreshTimer: Timer?

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Window Size Limits".localized
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 660, height: 380)
        super.init(window: window)
        buildContent()
        window.center()
        observer = NotificationCenter.default.addObserver(forName: WindowSizeConstraints.changed, object: nil, queue: .main) { [weak self] _ in
            // Store notifications can arrive during an AX lookup. Refresh after
            // that mutation has finished, without reentering the store.
            DispatchQueue.main.async { self?.reload() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard self?.window?.isVisible == true else { return }; self?.reload()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        refreshTimer?.invalidate()
    }

    override func showWindow(_ sender: Any?) {
        displayedRecords = nil
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        for (button, action) in [(resetWindow, #selector(resetSelectedWindow)), (resetApp, #selector(resetSelectedApplication)), (resetAll, #selector(resetEverything))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
        }
        resetWindow.setAccessibilityIdentifier("resetWindowSizeLimit")
        resetApp.setAccessibilityIdentifier("resetApplicationSizeLimits")
        resetAll.setAccessibilityIdentifier("resetAllWindowSizeLimits")
        let buttons = NSStackView(views: [resetWindow, resetApp, NSView(), resetAll])
        buttons.orientation = .horizontal
        buttons.distribution = .fill
        buttons.spacing = 8
        for (id, title, width) in [("window", "Application / Window".localized, 300.0), ("minimum", "Observed Size".localized, 130.0), ("reuse", "Observed For".localized, 240.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "window" ? 190 : 100
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        outline.delegate = self; outline.dataSource = self
        outline.rowHeight = 28
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = false
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.setAccessibilityIdentifier("windowSizeLimitsList")
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        let views: [NSView] = [scroll, buttons]
        views.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        for view in views {
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20).isActive = true
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20).isActive = true
        }
    }

    private func reload() {
        let selected = outline.item(atRow: outline.selectedRow)
        let selectedID = (selected as? Row)?.record.id
        let selectedBundle = (selected as? Group)?.bundleID
        let records = WindowSizeConstraints.shared.records
        let remembers = WindowSizeConstraints.shared.rememberLimits
        guard displayedRecords != records || displayedRememberState != remembers else { return }
        displayedRecords = records; displayedRememberState = remembers
        let existingGroups = Set(groups.map(\.bundleID))
        let expandedGroups = Set(groups.filter { outline.isItemExpanded($0) }.map(\.bundleID))
        let newGroups = Dictionary(grouping: records, by: { $0.identity.bundleID }).map { bundleID, windows in
            Group(bundleID: bundleID, name: windows.first?.appName ?? bundleID, windows: windows)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        groups = newGroups
        outline.reloadData()
        for group in groups where !existingGroups.contains(group.bundleID) || expandedGroups.contains(group.bundleID) {
            outline.expandItem(group)
        }
        for row in 0..<outline.numberOfRows {
            let item = outline.item(atRow: row)
            if (selectedID != nil && (item as? Row)?.record.id == selectedID)
                || (selectedBundle != nil && (item as? Group)?.bundleID == selectedBundle) {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); break
            }
        }
        updateButtons()
    }

    private func updateButtons() {
        let item = outline.item(atRow: outline.selectedRow)
        resetWindow.isEnabled = item is Row
        resetApp.isEnabled = item is Group || item is Row
        resetAll.isEnabled = !groups.isEmpty
    }

    @objc private func resetSelectedWindow() {
        guard let row = outline.item(atRow: outline.selectedRow) as? Row else { return }
        let record = row.record
        WindowSizeConstraints.shared.reset(recordID: record.id); reload()
    }
    @objc private func resetSelectedApplication() {
        let item = outline.item(atRow: outline.selectedRow)
        guard let bundleID = (item as? Group)?.bundleID ?? (item as? Row)?.record.identity.bundleID else { return }
        WindowSizeConstraints.shared.reset(application: bundleID); reload()
    }
    @objc private func resetEverything() { WindowSizeConstraints.shared.resetAll(); reload() }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? groups.count : (item as? Group)?.windows.count ?? 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? Group { return group.windows[index] }
        return groups[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is Group }
    func outlineViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let text: String
        if let group = item as? Group {
            text = tableColumn?.identifier.rawValue == "window" ? "\(group.name) (\(group.windows.count))" : ""
        } else if let row = item as? Row {
            let record = row.record
            switch tableColumn?.identifier.rawValue {
            case "window":
                // WindowServer titles avoid synchronously querying a slow app
                // while drawing the management table. Titles are never saved.
                let rows = WindowProcessIdentity.launchTime(for: record.identity.pid) == record.identity.launch
                    ? CGWindowListCopyWindowInfo(.optionIncludingWindow, record.identity.windowID) as? [[String: Any]] : nil
                let title = rows?.first?[kCGWindowName as String] as? String
                text = title?.isEmpty == false ? title! : String(format: "Window %u".localized, record.identity.windowID)
            case "minimum":
                let size = record.evidence.learned
                text = "\(size.width > 0 ? String(Int(size.width.rounded())) : "—") × \(size.height > 0 ? String(Int(size.height.rounded())) : "—") pt"
            default:
                if !WindowSizeConstraints.shared.rememberLimits { text = "10 minutes".localized }
                else { text = "This open window".localized }
            }
        } else { return nil }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        if item is Group { label.font = .boldSystemFont(ofSize: NSFont.systemFontSize) }
        return label
    }
}
