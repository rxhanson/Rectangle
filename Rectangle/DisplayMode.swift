/// DisplayMode.swift

import Cocoa

struct DisplayOption: Equatable {
    let screens: [CGDirectDisplayID]
    let mirror: Bool

    struct Setting: Equatable {
        var enabled = true
        var mirrorOf = kCGNullDirectDisplay
    }

    /// Every combination of screens, smallest first, then mirroring. `numbered` is in screen-number order.
    // ponytail: every subset, so 5+ screens give 31+ rows; trim to singles plus all if anyone has that many.
    static func options(for numbered: [CGDirectDisplayID], canTurnOff: Bool) -> [DisplayOption] {
        let all = Array(numbered.indices)
        var subsets: [[Int]] = [all]
        if canTurnOff {
            let masks = 1..<(1 << numbered.count)
            subsets = masks.map { (mask: Int) -> [Int] in all.filter { mask & (1 << $0) != 0 } }
            subsets.sort { (a: [Int], b: [Int]) -> Bool in
                a.count != b.count ? a.count < b.count : a.lexicographicallyPrecedes(b)
            }
        }
        var options = subsets.map { DisplayOption(screens: $0.map { numbered[$0] }, mirror: false) }
        if numbered.count > 1 {
            options.append(DisplayOption(screens: numbered, mirror: true))
        }
        return options
    }

    func configuration(displays: [CGDirectDisplayID], main: CGDirectDisplayID) -> [CGDirectDisplayID: Setting] {
        var settings = [CGDirectDisplayID: Setting]()
        for display in displays {
            settings[display] = mirror
                ? Setting(mirrorOf: display == main ? kCGNullDirectDisplay : main)
                : Setting(enabled: screens.contains(display))
        }
        return settings
    }
}

final class DisplayModeManager {
    static let shared = DisplayModeManager()

    private typealias SetDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    /// Private SkyLight call: there is no public API that turns a display off.
    private static let setDisplayEnabled: SetDisplayEnabled? = {
        // RTLD_DEFAULT, which Swift doesn't import.
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") ?? dlsym(handle, "SLSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(symbol, to: SetDisplayEnabled.self)
    }()

    /// Displays turned off here may drop out of the online list, so they're remembered.
    private var disabled = Set<CGDirectDisplayID>()
    private var numbers = [CGDirectDisplayID: Int]()
    private var names = [CGDirectDisplayID: String]()
    private var screenObserver: NSObjectProtocol?
    private var panel: DisplayModePanel?
    private var badges: [ScreenNumberBadge] = []

    var hasMultipleDisplays: Bool { displays().count > 1 }

    func showPicker() {
        if let panel {
            panel.selectNext()
            return
        }
        let displays = numberedDisplays()
        let mouse = NSEvent.mouseLocation
        guard displays.count > 1,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else {
            NSSound.beep()
            return
        }

        let options = DisplayOption.options(for: displays, canTurnOff: Self.setDisplayEnabled != nil)
        let rows = options.map { (title: title(for: $0), subtitle: $0.screens.map(name).joined(separator: ", ")) }
        let panel = DisplayModePanel(rows: rows, selected: options.firstIndex(of: currentOption(displays)) ?? 0, screen: screen,
                                     onChoose: { [weak self] index in
                                         self?.closePanel()
                                         self?.apply(options[index], displays: displays)
                                     },
                                     onCancel: { [weak self] in self?.closePanel() })
        self.panel = panel
        badges = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID, let number = numbers[id] else { return nil }
            return ScreenNumberBadge(number: number, screen: screen)
        }
        badges.forEach { $0.orderFrontRegardless() }
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        let panel = self.panel
        self.panel = nil
        panel?.dismiss()
        badges.forEach { $0.orderOut(nil) }
        badges = []
    }

    private func apply(_ option: DisplayOption, displays: [CGDirectDisplayID]) {
        guard option != currentOption(displays) else { return }

        // Turn everything back on first, in its own pass, before mirroring or turning off another display.
        let allOn = DisplayOption(screens: displays, mirror: false)
        if !disabled.isEmpty {
            guard reconfigure(allOn.configuration(displays: displays, main: CGMainDisplayID())) else { return }
            if option == allOn { return }
        }
        reconfigure(option.configuration(displays: displays, main: CGMainDisplayID()))
    }

    private func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var online = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &online, &count)
        return Set(online.prefix(Int(count))).union(disabled).sorted()
    }

    private func isMirroring(_ displays: [CGDirectDisplayID]) -> Bool {
        displays.contains { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
    }

    /// Numbers are only reassigned while every display is on and unmirrored, so
    /// "Screen 2" keeps meaning the same display while another one is off.
    private func numberedDisplays() -> [CGDirectDisplayID] {
        let displays = displays()
        if disabled.isEmpty, !isMirroring(displays) {
            numbers = [:]
            for (index, screen) in ScreenDetection().order(screens: NSScreen.screens).enumerated() {
                guard let id = screen.displayID else { continue }
                numbers[id] = index + 1
                names[id] = screen.localizedName
            }
        }
        for display in displays where numbers[display] == nil {
            numbers[display] = (numbers.values.max() ?? 0) + 1
        }
        return displays.sorted { numbers[$0, default: 0] < numbers[$1, default: 0] }
    }

    private func currentOption(_ displays: [CGDirectDisplayID]) -> DisplayOption {
        isMirroring(displays)
            ? DisplayOption(screens: displays, mirror: true)
            : DisplayOption(screens: displays.filter { !disabled.contains($0) }, mirror: false)
    }

    private func title(for option: DisplayOption) -> String {
        if option.mirror { return String(localized: "Mirror All Screens") }
        let numbers = option.screens.map { self.numbers[$0, default: 0] }
        if numbers.count == 1 { return String(localized: "Screen \(numbers[0]) Only") }
        return String(localized: "Screens \(numbers.map(String.init).joined(separator: " + "))")
    }

    private func name(_ display: CGDirectDisplayID) -> String {
        names[display] ?? String(localized: "Screen \(numbers[display, default: 0])")
    }

    @discardableResult
    private func reconfigure(_ settings: [CGDirectDisplayID: DisplayOption.Setting]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return fail("begin") }

        for (display, setting) in settings {
            if !setting.enabled || disabled.contains(display) {
                guard let setDisplayEnabled = Self.setDisplayEnabled else {
                    CGCancelDisplayConfiguration(config)
                    return fail("no private display API")
                }
                // Re-enabling a display that was unplugged while off fails, and that's fine.
                if setDisplayEnabled(config, display, setting.enabled) != .success, !setting.enabled {
                    CGCancelDisplayConfiguration(config)
                    return fail("turn off display \(display)")
                }
            }
            if setting.enabled, CGDisplayMirrorsDisplay(display) != setting.mirrorOf {
                CGConfigureDisplayMirrorOfDisplay(config, display, setting.mirrorOf)
            }
        }

        let turnsOff = settings.values.contains { !$0.enabled }
        // App-only, so quitting Rectangle turns a display back on.
        let result = CGCompleteDisplayConfiguration(config, turnsOff ? .forAppOnly : .permanently)
        guard result == .success else { return fail("complete (\(result.rawValue))") }

        disabled = Set(settings.filter { !$0.value.enabled }.keys)
        updateScreenObserver()
        return true
    }

    /// While a display is off, turn it back on if every display left on goes away.
    private func updateScreenObserver() {
        if disabled.isEmpty {
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
        } else if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
                guard let self, !self.disabled.isEmpty, self.displays().allSatisfy(self.disabled.contains) else { return }
                let disabled = Array(self.disabled)
                self.reconfigure(DisplayOption(screens: disabled, mirror: false).configuration(displays: disabled, main: CGMainDisplayID()))
            }
        }
    }

    private func fail(_ step: String) -> Bool {
        Logger.log("Display mode: \(step) failed")
        NSSound.beep()
        return false
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private final class ScreenNumberBadge: NSPanel {
    static let size: CGFloat = 180

    override var canBecomeKey: Bool { false }

    init(number: Int, screen: NSScreen) {
        let frame = NSRect(x: screen.frame.midX - Self.size / 2, y: screen.frame.midY - Self.size / 2,
                           width: Self.size, height: Self.size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let box = NSView(frame: NSRect(origin: .zero, size: frame.size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        box.layer?.borderColor = NSColor.white.cgColor
        box.layer?.borderWidth = 6
        box.layer?.cornerRadius = 28
        box.layer?.cornerCurve = .continuous

        let label = NSTextField(labelWithString: String(number))
        label.font = .systemFont(ofSize: 110, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        contentView = box
    }
}

/// Win+P-style list. Pressing the shortcut again moves the highlight; letting go of
/// its modifiers after that applies it, like Cmd+Tab. A single press leaves it open.
private final class DisplayModePanel: NSPanel {
    private static let rowHeight: CGFloat = 40
    private static let padding: CGFloat = 6
    private let onChoose: (Int) -> Void
    private let onCancel: () -> Void
    private var rows: [DisplayModeRowView] = []
    private var selectedIndex = 0
    private var cycled = false
    private var flagsMonitor: Any?

    override var canBecomeKey: Bool { true }

    init(rows items: [(title: String, subtitle: String)], selected: Int, screen: NSScreen,
         onChoose: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.onChoose = onChoose
        self.onCancel = onCancel
        let size = NSSize(width: 320, height: CGFloat(items.count) * Self.rowHeight + Self.padding * 2)
        // Just below the screen's number badge, so the badge stays visible.
        let top = screen.frame.midY - ScreenNumberBadge.size / 2 - 16
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: max(screen.visibleFrame.minY + 8, top - size.height),
                           width: size.width, height: size.height)

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        for (index, item) in items.enumerated() {
            let row = DisplayModeRowView(title: item.title, subtitle: item.subtitle,
                                         onHover: { [weak self] in self?.select(index) },
                                         onClick: { [weak self] in self?.onChoose(index) })
            row.frame = NSRect(x: Self.padding, y: size.height - Self.padding - CGFloat(index + 1) * Self.rowHeight,
                               width: size.width - Self.padding * 2, height: Self.rowHeight)
            container.addSubview(row)
            rows.append(row)
        }
        contentView = container
        select(selected)

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self, self.cycled, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                self.onChoose(self.selectedIndex)
            }
            return event
        }
    }

    func selectNext() {
        cycled = true
        select((selectedIndex + 1) % rows.count)
    }

    func dismiss() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        onCancel()
    }

    override func keyDown(with event: NSEvent) {
        // The shortcut's modifiers may still be held, so they don't stop the arrows.
        let key = StackBadgeManager.navigationKey(forKeyCode: event.keyCode, modifiers: [])
        switch key {
        case .up?, .down?:
            if let index = StackBadgeManager.selection(from: selectedIndex, movedBy: key == .up ? -1 : 1, count: rows.count) {
                select(index)
            }
        case .commit?: onChoose(selectedIndex)
        case .escape?: onCancel()
        case nil: break
        }
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        for (i, row) in rows.enumerated() {
            row.setSelected(i == index)
        }
    }
}

private final class DisplayModeRowView: NSView {
    private let onHover: () -> Void
    private let onClick: () -> Void
    private let titleField: NSTextField
    private let subtitleField: NSTextField

    init(title: String, subtitle: String, onHover: @escaping () -> Void, onClick: @escaping () -> Void) {
        self.onHover = onHover
        self.onClick = onClick
        titleField = NSTextField(labelWithString: title)
        subtitleField = NSTextField(labelWithString: subtitle)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleField.font = .systemFont(ofSize: 11)
        for field in [titleField, subtitleField] {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(title), \(subtitle)")
        setSelected(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.cgColor : nil
        titleField.textColor = selected ? .selectedMenuItemTextColor : .labelColor
        subtitleField.textColor = selected ? .selectedMenuItemTextColor : .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
