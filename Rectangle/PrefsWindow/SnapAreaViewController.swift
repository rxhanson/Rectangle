/// SnapAreaViewController.swift

import Cocoa

class SnapAreaViewController: NSViewController {
    private var layoutHelperCheckboxes: [NSButton] = []
    private var layoutHelperPermissionLabel: NSTextField?
    private var layoutHelperPermissionButton: NSButton?
    private var layoutHelperExamplePopover: NSPopover?

    @objc private func showLayoutHelperExample(_ sender: NSButton) {
        let controller = NSViewController()
        let screenshot = NSImageView()
        screenshot.image = NSImage(named: "LayoutHelperExample")
        screenshot.imageScaling = .scaleProportionallyUpOrDown
        screenshot.setAccessibilityLabel("Layout Helper example: Notes is snapped on the left; choose Research or Tasks to fill the right side.")
        screenshot.widthAnchor.constraint(equalToConstant: 560).isActive = true
        screenshot.heightAnchor.constraint(equalToConstant: 325).isActive = true
        let explanation = NSTextField(wrappingLabelWithString: "Snap a window, then choose another to fill the remaining space. Sample windows shown.\n\nThumbnails need Screen Recording access; icons and titles work without it.")
        explanation.widthAnchor.constraint(equalToConstant: 560).isActive = true
        explanation.setContentCompressionResistancePriority(.required, for: .vertical)
        let content = NSStackView(views: [screenshot, explanation])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        controller.view = container
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = container.fittingSize
        layoutHelperExamplePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func toggleLayoutHelper(_ sender: NSButton) {
        switch sender.tag {
        case 0: Defaults.layoutHelper.enabled = sender.state == .on
        case 1: Defaults.layoutHelperKeyboard.enabled = sender.state == .on
        default: Defaults.layoutHelperDenseGrids.enabled = sender.state == .on
        }
        LayoutHelperManager.shared.cancel()
        if sender.tag == 0, sender.state == .on {
            LayoutHelperPermission.guideIfNeeded { [weak self] in self?.refreshLayoutHelperSettings() }
        }
        refreshLayoutHelperSettings()
    }

    @objc private func enableLayoutHelperPreviews(_ sender: NSButton) {
        LayoutHelperManager.shared.cancel()
        LayoutHelperPermission.guideIfNeeded { [weak self] in self?.refreshLayoutHelperSettings() }
        refreshLayoutHelperSettings()
    }

    private func refreshLayoutHelperSettings() {
        let states = [Defaults.layoutHelper.userEnabled, Defaults.layoutHelperKeyboard.enabled, Defaults.layoutHelperDenseGrids.enabled]
        for (index, checkbox) in layoutHelperCheckboxes.enumerated() {
            checkbox.state = states[index] ? .on : .off
            checkbox.isEnabled = index == 0 || states[0]
        }
        let supported = LayoutHelperPermission.previewsSupported
        let allowed = LayoutHelperPermission.previewsAllowed
        layoutHelperPermissionLabel?.isHidden = !states[0]
        layoutHelperPermissionLabel?.stringValue = !supported
            ? "Window thumbnails require macOS 14 or later."
            : allowed ? "Window thumbnails enabled."
            : "Thumbnails need Screen Recording access. Icons and titles work without it."
        layoutHelperPermissionButton?.isHidden = !states[0] || !supported || allowed
    }
    
    @IBOutlet weak var windowSnappingCheckbox: NSButton!
    @IBOutlet weak var unsnapRestoreButton: NSButton!
    @IBOutlet weak var animateFootprintCheckbox: NSButton!
    @IBOutlet weak var blurFootprintCheckbox: NSButton!
    @IBOutlet weak var experimentalWindowAnimationsCheckbox: NSButton!
    @IBOutlet weak var hapticFeedbackCheckbox: NSButton!
    @IBOutlet weak var missionControlDraggingCheckbox: NSButton!
    private let blurAppearanceSelect = NSPopUpButton(frame: .zero, pullsDown: false)

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
        blurFootprintCheckbox.state = Defaults.footprintBlur.enabled ? .on : .off
        experimentalWindowAnimationsCheckbox.state = Defaults.experimentalWindowAnimations.enabled ? .on : .off
        blurAppearanceSelect.selectItem(withTag: Defaults.blurAppearance.value.rawValue)
        blurAppearanceSelect.isEnabled = Defaults.footprintBlur.enabled
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
        super.viewDidLoad()
        if let animationStack = blurFootprintCheckbox.superview as? NSStackView,
           let optionsRow = animationStack.superview as? NSStackView,
           let contentStack = optionsRow.superview as? NSStackView {
            let section = NSStackView()
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = 14
            section.setAccessibilityIdentifier("layoutHelperSection")
            let separator = NSBox()
            separator.boxType = .separator
            contentStack.addArrangedSubview(separator)
            contentStack.addArrangedSubview(section)
            separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            section.leadingAnchor.constraint(equalTo: optionsRow.leadingAnchor).isActive = true
            section.trailingAnchor.constraint(equalTo: optionsRow.trailingAnchor).isActive = true

            func checkbox(_ title: String, tag: Int) -> NSButton {
                let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleLayoutHelper(_:)))
                button.tag = tag
                button.setContentCompressionResistancePriority(.required, for: .vertical)
                layoutHelperCheckboxes.append(button)
                return button
            }
            let master = checkbox("Layout Helper", tag: 0)
            let example = NSButton(title: "See example…", target: self, action: #selector(showLayoutHelperExample(_:)))
            example.bezelStyle = .rounded
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let header = NSStackView(views: [master, spacer, example])
            header.orientation = .horizontal
            header.alignment = .centerY
            section.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

            func formRow(_ title: String, content: NSView) {
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                label.textColor = .secondaryLabelColor
                label.widthAnchor.constraint(equalToConstant: 116).isActive = true
                let row = NSStackView(views: [label, content])
                row.orientation = .horizontal
                row.alignment = .top
                row.spacing = 16
                row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)
                section.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
            }
            let options = NSStackView(views: [checkbox("Keyboard and menu snaps", tag: 1),
                                            checkbox("Grids with eight or more cells", tag: 2)])
            options.orientation = .vertical
            options.alignment = .leading
            options.spacing = 8
            formRow("Also enable for", content: options)

            let permissionButton = NSButton(title: "Enable previews…", target: self, action: #selector(enableLayoutHelperPreviews(_:)))
            permissionButton.bezelStyle = .rounded
            permissionButton.setContentCompressionResistancePriority(.required, for: .vertical)
            layoutHelperPermissionButton = permissionButton
            let permissionLabel = NSTextField(wrappingLabelWithString: "")
            permissionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            permissionLabel.textColor = .secondaryLabelColor
            permissionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            layoutHelperPermissionLabel = permissionLabel
            let previews = NSStackView(views: [permissionButton, permissionLabel])
            previews.orientation = .vertical
            previews.alignment = .leading
            previews.spacing = 6
            formRow("Window previews", content: previews)
            permissionLabel.widthAnchor.constraint(equalTo: previews.widthAnchor).isActive = true
        }
        refreshLayoutHelperSettings()
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
            self?.refreshLayoutHelperSettings()
        })
        Notification.Name.defaultSnapAreas.onPost(using: { [weak self] _ in
            self?.loadSnapAreas()
        })
        Notification.Name.appWillBecomeActive.onPost() { [weak self] _ in
            self?.showHidePortrait()
            self?.refreshLayoutHelperSettings()
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
        refreshLayoutHelperSettings()
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
