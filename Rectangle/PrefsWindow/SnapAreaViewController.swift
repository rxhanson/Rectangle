/// SnapAreaViewController.swift

import Cocoa

class SnapAreaViewController: NSViewController {
    
    @IBOutlet weak var windowSnappingCheckbox: NSButton!
    @IBOutlet weak var unsnapRestoreButton: NSButton!
    @IBOutlet weak var animateFootprintCheckbox: NSButton!
    @IBOutlet weak var blurFootprintCheckbox: NSButton!
    @IBOutlet weak var experimentalWindowAnimationsCheckbox: NSButton!
    @IBOutlet weak var hapticFeedbackCheckbox: NSButton!
    @IBOutlet weak var missionControlDraggingCheckbox: NSButton!
    private let blurAppearanceSelect = NSPopUpButton(frame: .zero, pullsDown: false)
    private let windowAnimationStyleSelect = NSPopUpButton(frame: .zero, pullsDown: false)

    @IBOutlet weak var topLeftLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var topLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var topRightLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var leftLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var rightLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var bottomLeftLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var bottomLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var bottomRightLandscapeSelect: NSPopUpButton!
    
    @IBOutlet weak var portraitStackView: NSStackView!
    
    @IBOutlet weak var topLeftPortraitSelect: NSPopUpButton!
    @IBOutlet weak var topPortraitSelect: NSPopUpButton!
    @IBOutlet weak var topRightPortraitSelect: NSPopUpButton!
    @IBOutlet weak var leftPortraitSelect: NSPopUpButton!
    @IBOutlet weak var rightPortraitSelect: NSPopUpButton!
    @IBOutlet weak var bottomLeftPortraitSelect: NSPopUpButton!
    @IBOutlet weak var bottomPortraitSelect: NSPopUpButton!
    @IBOutlet weak var bottomRightPortraitSelect: NSPopUpButton!
    
    @IBAction func toggleWindowSnapping(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.windowSnapping.enabled = newSetting
        Notification.Name.windowSnapping.post(object: newSetting)
        if newSetting {
            MacTilingDefaults.checkForBuiltInTiling(skipIfAlreadyNotified: false)
        }
    }
    
    @IBAction func toggleUnsnapRestore(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.unsnapRestore.enabled = newSetting
    }
    
    @IBAction func toggleAnimateFootprint(_ sender: NSButton) {
        let newSetting: Float = sender.state == .on ? 0.75 : 0
        Defaults.footprintAnimationDurationMultiplier.value = newSetting
    }

    @IBAction func toggleBlurFootprint(_ sender: NSButton) {
        Defaults.footprintBlur.enabled = sender.state == .on
        refreshWindowAnimationPreferences()
    }

    @IBAction func toggleExperimentalWindowAnimations(_ sender: NSButton) {
        Defaults.experimentalWindowAnimations.enabled = sender.state == .on
        refreshWindowAnimationPreferences()
        Notification.Name.windowAnimationPreferencesChanged.post()
    }

    private func refreshWindowAnimationPreferences() {
        Defaults.normalizeWindowAnimationPreferences()
        blurFootprintCheckbox.state = Defaults.footprintBlur.enabled ? .on : .off
        blurFootprintCheckbox.isEnabled = !(Defaults.experimentalWindowAnimations.enabled && Defaults.windowAnimationStyle.value == .frosted)
        experimentalWindowAnimationsCheckbox.state = Defaults.experimentalWindowAnimations.enabled ? .on : .off
        windowAnimationStyleSelect.selectItem(withTag: Defaults.windowAnimationStyle.value.rawValue)
        windowAnimationStyleSelect.isEnabled = Defaults.experimentalWindowAnimations.enabled
        blurAppearanceSelect.selectItem(withTag: Defaults.blurAppearance.value.rawValue)
        blurAppearanceSelect.isEnabled = Defaults.footprintBlur.enabled
    }

    private func configureWindowAnimationStyle() {
        guard let stack = experimentalWindowAnimationsCheckbox.superview as? NSStackView,
              let index = stack.arrangedSubviews.firstIndex(of: experimentalWindowAnimationsCheckbox) else { return }
        let label = NSTextField(labelWithString: NSLocalizedString("Animation style", tableName: "Main", comment: "Window animation style setting"))
        for (style, title) in [(WindowAnimationStyle.frosted, NSLocalizedString("Blur preview", tableName: "Main", comment: "Window animation style using a blurred preview")),
                               (.direct, NSLocalizedString("Direct resize", tableName: "Main", comment: "Animate the actual window's position and size"))] {
            windowAnimationStyleSelect.addItem(withTitle: title)
            windowAnimationStyleSelect.lastItem?.tag = style.rawValue
        }
        windowAnimationStyleSelect.setAccessibilityLabel(label.stringValue)
        windowAnimationStyleSelect.target = self
        windowAnimationStyleSelect.action = #selector(setWindowAnimationStyle(_:))
        let row = NSStackView(views: [label, windowAnimationStyleSelect])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        stack.insertArrangedSubview(row, at: index + 1)
    }

    @objc private func setWindowAnimationStyle(_ sender: NSPopUpButton) {
        guard let style = WindowAnimationStyle(rawValue: sender.selectedTag()) else { return }
        Defaults.windowAnimationStyle.value = style
        refreshWindowAnimationPreferences()
        Notification.Name.windowAnimationPreferencesChanged.post()
    }

    private func configureBlurAppearance() {
        guard let stack = blurFootprintCheckbox.superview as? NSStackView else { return }
        let label = NSTextField(labelWithString: NSLocalizedString("Blur appearance", tableName: "Main", comment: "Preview blur appearance setting"))
        let titles = [NSLocalizedString("Follow System", tableName: "Main", comment: "Use the system appearance"),
                      NSLocalizedString("Light", tableName: "Main", comment: "Light preview blur"),
                      NSLocalizedString("Dark", tableName: "Main", comment: "Dark preview blur")]
        for (mode, title) in zip(BlurAppearance.allCases, titles) {
            blurAppearanceSelect.addItem(withTitle: title)
            blurAppearanceSelect.lastItem?.tag = mode.rawValue
        }
        blurAppearanceSelect.setAccessibilityLabel(label.stringValue)
        blurAppearanceSelect.target = self
        blurAppearanceSelect.action = #selector(setBlurAppearance(_:))
        let row = NSStackView(views: [label, blurAppearanceSelect])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        stack.addArrangedSubview(row)
    }

    @objc private func setBlurAppearance(_ sender: NSPopUpButton) {
        guard let appearance = BlurAppearance(rawValue: sender.selectedTag()) else { return }
        Defaults.blurAppearance.value = appearance
    }
    
    @IBAction func toggleHapticFeedback(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.hapticFeedbackOnSnap.enabled = newSetting
    }
    
    @IBAction func toggleMissionControlDragging(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .off
        Defaults.missionControlDragging.enabled = newSetting
        Notification.Name.missionControlDragging.post(object: newSetting)
    }
    
    @IBAction func setLandscapeSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .landscape)
    }

    @IBAction func setPortraitSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .portrait)
    }
    
    private func setSnapArea(sender: NSPopUpButton, type: DisplayOrientation) {
        guard let directional = Directional(rawValue: sender.tag) else { return }
        let selectedTag = sender.selectedTag()
        var snapAreaConfig: SnapAreaConfig?
        if selectedTag < -1, let compound = CompoundSnapArea(rawValue: selectedTag) {
           snapAreaConfig = SnapAreaConfig(compound: compound)
        } else if selectedTag > -1, let action = WindowAction(rawValue: selectedTag) {
            snapAreaConfig = SnapAreaConfig(action: action)
        }
        SnapAreaModel.instance.setConfig(type: type, directional: directional, snapAreaConfig: snapAreaConfig)
    }
    
    override func viewDidLoad() {
        configureWindowAnimationStyle()
        configureBlurAppearance()
        windowSnappingCheckbox.state = Defaults.windowSnapping.userDisabled ? .off : .on
        unsnapRestoreButton.state = Defaults.unsnapRestore.userDisabled ? .off : .on
        animateFootprintCheckbox.state = Defaults.footprintAnimationDurationMultiplier.value > 0 ? .on : .off
        refreshWindowAnimationPreferences()
        hapticFeedbackCheckbox.state = Defaults.hapticFeedbackOnSnap.userEnabled ? .on : .off
        missionControlDraggingCheckbox.state = Defaults.missionControlDragging.userDisabled ? .on : .off
        missionControlDraggingCheckbox.isHidden = !Defaults.missionControlDragging.userDisabled
        showHidePortrait()
        
        Notification.Name.configImported.onPost(using: { [weak self] _ in
            self?.refreshWindowAnimationPreferences()
            self?.loadSnapAreas()
        })
        Notification.Name.defaultSnapAreas.onPost(using: { [weak self] _ in
            self?.loadSnapAreas()
        })
        Notification.Name.appWillBecomeActive.onPost() { [weak self] _ in
            self?.showHidePortrait()
        }
        Notification.Name.windowSnapping.onPost { [weak self] _ in
            self?.windowSnappingCheckbox.state = Defaults.windowSnapping.userDisabled ? .off : .on
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { [weak self] _ in
            self?.showHidePortrait()
        }
    }
    
    func showHidePortrait() {
        portraitStackView.isHidden = !NSScreen.portraitDisplayConnected
    }
    
    // Only load the selects when the view appears, to fix a performance issue where switching to this tab was taking a long time to load
    var selectsLoaded = false
    override func viewWillAppear() {
        refreshWindowAnimationPreferences()
        animateFootprintCheckbox.state = Defaults.footprintAnimationDurationMultiplier.value > 0 ? .on : .off
        if !selectsLoaded {
            loadSnapAreas()
            selectsLoaded = true
        }
    }
    
    func loadSnapAreas() {

        let landscapeSelects: [NSPopUpButton] = [
            topLeftLandscapeSelect,
            topLandscapeSelect,
            topRightLandscapeSelect,
            leftLandscapeSelect,
            rightLandscapeSelect,
            bottomLeftLandscapeSelect,
            bottomLandscapeSelect,
            bottomRightLandscapeSelect
        ]

        let portraitSelects: [NSPopUpButton] = [
            topLeftPortraitSelect,
            topPortraitSelect,
            topRightPortraitSelect,
            leftPortraitSelect,
            rightPortraitSelect,
            bottomLeftPortraitSelect,
            bottomPortraitSelect,
            bottomRightPortraitSelect
        ]
        
        landscapeSelects.forEach { initialize(select: $0, orientation: .landscape)}
        portraitSelects.forEach { initialize(select: $0, orientation: .portrait)}
    }
    
    /// Fix a performance bug by loading only selected menu items first, then dispatching async to fill out all menu items
    private func initialize(select: NSPopUpButton, orientation: DisplayOrientation) {
        
        defer {
            DispatchQueue.main.async {
                self.configure(select: select, orientation: orientation)
            }
        }
        
        guard let directional = Directional(rawValue: select.tag) else { return }
        
        reset(select: select)
        let selectedTag = getSelectedTag(for: directional, orientation: orientation)
        
        for compoundSnapArea in CompoundSnapArea.all {
            guard compoundSnapArea.compatibleOrientation.contains(orientation), compoundSnapArea.compatibleDirectionals.contains(directional) else { continue }
            if selectedTag == compoundSnapArea.rawValue {
                addCompoundSnapAreaMenuItem(for: compoundSnapArea, to: select, isSelected: true)
                return
            }
        }
        
        for windowAction in WindowAction.active {
            if windowAction.isDragSnappable, selectedTag == windowAction.rawValue {
                addWindowActionMenuItem(for: windowAction, to: select, isSelected: true)
                return
            }
        }
    }
    
    private func configure(select: NSPopUpButton, orientation: DisplayOrientation) {
        guard let directional = Directional(rawValue: select.tag) else { return }
        
        reset(select: select)
        let selectedTag = getSelectedTag(for: directional, orientation: orientation)

        for compoundSnapArea in CompoundSnapArea.all {
            guard compoundSnapArea.compatibleOrientation.contains(orientation), compoundSnapArea.compatibleDirectionals.contains(directional) else { continue }
            
            addCompoundSnapAreaMenuItem(for: compoundSnapArea, to: select, isSelected: selectedTag == compoundSnapArea.rawValue)
        }
        
        select.menu?.addItem(NSMenuItem.separator())
        
        for windowAction in WindowAction.active {
            if windowAction.isDragSnappable {
                addWindowActionMenuItem(for: windowAction, to: select, isSelected: selectedTag == windowAction.rawValue)
            }
        }
    }
    
    // MARK: - Menu Item & Setup Helpers
    
    private func reset(select: NSPopUpButton) {
        select.removeAllItems()
        select.addItem(withTitle: "-")
        select.menu?.items.first?.tag = -1
    }
    
    private func getSelectedTag(for directional: Directional, orientation: DisplayOrientation) -> Int {
        let snapAreaConfig = orientation == .landscape
            ? SnapAreaModel.instance.landscape[directional]
            : SnapAreaModel.instance.portrait[directional]
        
        return snapAreaConfig?.action?.rawValue ?? snapAreaConfig?.compound?.rawValue ?? -1
    }
    
    private func addCompoundSnapAreaMenuItem(for compoundSnapArea: CompoundSnapArea, to select: NSPopUpButton, isSelected: Bool) {
        let item = NSMenuItem(title: compoundSnapArea.displayName, action: nil, keyEquivalent: "")
        item.tag = compoundSnapArea.rawValue
        select.menu?.addItem(item)
        
        if isSelected {
            select.select(item)
        }
    }
    
    private func addWindowActionMenuItem(for windowAction: WindowAction, to select: NSPopUpButton, isSelected: Bool) {
        guard let name = windowAction.displayName else { return }
        
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.tag = windowAction.rawValue
        item.image = windowAction.image.copy() as? NSImage
        item.image?.size.height = 12
        item.image?.size.width = 18
        select.menu?.addItem(item)
        
        if isSelected {
            select.select(item)
        }
    }
}
