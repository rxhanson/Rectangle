/// SettingsViewController.swift

import Cocoa
import Sparkle
import MASShortcut

class SettingsViewController: NSViewController {
        
    @IBOutlet weak var launchOnLoginCheckbox: NSButton!
    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var hideMenuBarIconCheckbox: NSButton!
    @IBOutlet weak var subsequentExecutionPopUpButton: NSPopUpButton!
    @IBOutlet weak var allowAnyShortcutCheckbox: NSButton!
    @IBOutlet weak var checkForUpdatesAutomaticallyCheckbox: NSButton!
    @IBOutlet weak var checkForUpdatesButton: NSButton!
    @IBOutlet weak var gapSlider: NSSlider!
    @IBOutlet weak var gapLabel: NSTextField!
    @IBOutlet weak var skipGapTopEdgeCheckbox: NSButton!
    @IBOutlet weak var cursorAcrossCheckbox: NSButton!
    @IBOutlet weak var useCursorScreenDetectionCheckbox: NSButton!
    @IBOutlet weak var doubleClickTitleBarCheckbox: NSButton!
    @IBOutlet weak var todoCheckbox: NSButton!
    @IBOutlet weak var todoView: NSStackView!
    @IBOutlet weak var todoAppWidthField: AutoSaveFloatField!
    @IBOutlet weak var todoAppWidthUnitPopUpButton: NSPopUpButton!
    @IBOutlet weak var todoAppSidePopUpButton: NSPopUpButton!
    @IBOutlet weak var toggleTodoShortcutView: MASShortcutView!
    @IBOutlet weak var reflowTodoShortcutView: MASShortcutView!
    @IBOutlet weak var stageView: NSStackView!
    @IBOutlet weak var stageSlider: NSSlider!
    @IBOutlet weak var stageLabel: NSTextField!

    @IBOutlet weak var cycleSizesView: NSStackView!

    @IBOutlet var cycleSizesViewHeightConstraint: NSLayoutConstraint!

    @IBOutlet var todoViewHeightConstraint: NSLayoutConstraint!

    @IBOutlet weak var extraSettingsButton: NSButton!

    private var aboutTodoWindowController: NSWindowController?
    
    private var cycleSizeCheckboxes = [NSButton]()
    private var cornerCycleExpansionAxisButtons = [NSButton]()
    private var cooperativeCornerResizeCheckbox: NSButton?
    
    private var combinedDisplayModeCheckbox: NSButton?
    private var greenButtonOverrideCheckbox: NSButton?
    private var autoMaximizeCheckbox: NSButton?
    
    // Used in extras popover extension
    var extraSettingsPopover: NSPopover?
    var tilingShortcutViews = [MASShortcutView]()
    let shortcutRecordingObserver = ShortcutRecordingObserver()
    var tileGridLimitRows = [TileGridLimitRow]()
    var halvesPreserveOtherAxisSizeCheckbox: NSButton?
    var stackBadgeCheckbox: NSButton?
    var repeatedMaximizeRestoresPreviousCheckbox: NSButton?

    @IBAction func toggleLaunchOnLogin(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        LaunchOnLogin.isEnabled = newSetting
        Defaults.launchOnLogin.enabled = newSetting
    }
    
    @IBAction func toggleHideMenuBarIcon(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.hideMenuBarIcon.enabled = newSetting
        RectangleStatusItem.instance.refreshVisibility()
    }

    @IBAction func setSubsequentExecutionBehavior(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        guard let mode = SubsequentExecutionMode(rawValue: tag) else {
            Logger.log("Expected a pop up button to have a selected item with a valid tag matching a value of SubsequentExecutionMode. Got: \(String(describing: tag))")
            return
        }

        Defaults.subsequentExecutionMode.value = mode
        initializeCycleSizesView(animated: true)
    }
    
    @IBAction func toggleSkipGapTopEdge(_ sender: NSButton) {
        Defaults.skipGapTopEdge.enabled = sender.state == .on
    }

    @IBAction func gapSliderChanged(_ sender: NSSlider) {
        gapLabel.stringValue = "\(sender.intValue) px"
        if let event = NSApp.currentEvent {
            if event.type == .leftMouseUp || event.type == .keyDown {
                if Float(sender.intValue) != Defaults.gapSize.value {
                    Defaults.gapSize.value = Float(sender.intValue)
                    skipGapTopEdgeCheckbox.isHidden = Defaults.gapSize.value == 0
                }
            }
        }
    }
    
    @IBAction func toggleCursorMove(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.moveCursorAcrossDisplays.enabled = newSetting
    }

    @IBAction func toggleUseCursorScreenDetection(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.useCursorScreenDetection.enabled = newSetting
    }

    @IBAction func toggleAllowAnyShortcut(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.allowAnyShortcut.enabled = newSetting
        Notification.Name.allowAnyShortcut.post(object: newSetting)
        let validator = newSetting ? PassthroughShortcutValidator() : MASShortcutValidator()
        tilingShortcutViews.forEach { $0.shortcutValidator = validator }
    }
    
    @objc func toggleShowAdditionalSizesInMenu(_ sender: NSButton) {
        let enabled: Bool = sender.state == .on
        Defaults.showAdditionalSizesInMenu.enabled = enabled
        Notification.Name.showAdditionalSizesInMenuChanged.post()
    }

    @objc func toggleStackBadge(_ sender: NSButton) {
        Defaults.stackBadge.enabled = sender.state == .on
        Notification.Name.stackBadgeChanged.post()
    }

    @objc func toggleCyclingOverlapOffset(_ sender: NSButton) {
        Defaults.cyclingOverlapOffset.enabled = sender.state == .on
    }

    @objc func setCornerCycleExpansionAxis(_ sender: NSButton) {
        guard let axis = CornerCycleExpansionAxis(rawValue: sender.tag) else {
            Logger.log("Expected tag of cyclic corner expansion axis radio button to match a value of CornerCycleExpansionAxis. Got: \(String(describing: sender.tag))")
            return
        }

        Defaults.cornerCycleExpansionAxis.value = axis
        setToggleStatesForCornerCycleExpansionAxisButtons()
    }

    @objc func toggleCooperativeCornerResize(_ sender: NSButton) {
        Defaults.cooperativeCornerResize.enabled = sender.state == .on
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        AppDelegate.instance.updaterController?.checkForUpdates(sender)
    }
    
    @IBAction func toggleDoubleClickTitleBar(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        if newSetting && !TitleBarManager.systemSettingDisabled {
            
            var openSystemSettingsButtonName = NSLocalizedString("iWV-c2-BJD.title", tableName: "Main", value: "Open System Preferences", comment: "")
            
            openSystemSettingsButtonName = NSLocalizedString(
                "Open System Settings", tableName: "Main", value: "", comment: "")

            let conflictTitleText = NSLocalizedString(
                "Conflict with system setting", tableName: "Main", value: "", comment: "")
            let conflictDescriptionText = NSLocalizedString(
                "To let Rectangle manage the title bar double click functionality, you need to disable the corresponding macOS setting.", tableName: "Main", value: "", comment: "")

            
            let closeText = NSLocalizedString("DVo-aG-piG.title", tableName: "Main", value: "Close", comment: "")
            
            let response = AlertUtil.twoButtonAlert(question: conflictTitleText, text: conflictDescriptionText, confirmText: openSystemSettingsButtonName, cancelText: closeText)
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.dock")!)
            }
        }
        Defaults.doubleClickTitleBar.value = (newSetting ? WindowAction.maximize.rawValue : -1) + 1
        Notification.Name.windowTitleBar.post()
    }
    
    @objc func toggleCombinedDisplayMode(_ sender: NSButton) {
        Defaults.combinedDisplayMode.enabled = sender.state == .on
    }

    @objc func toggleGreenButtonOverride(_ sender: NSButton) {
        Defaults.greenButtonOverride.enabled = sender.state == .on
        Notification.Name.greenButtonOverride.post()
    }

    @objc func toggleAutoMaximize(_ sender: NSButton) {
        Defaults.autoMaximize.enabled = sender.state == .on
    }

    @objc func toggleHalvesPreserveOtherAxisSize(_ sender: NSButton) {
        Defaults.halvesPreserveOtherAxisSize.enabled = sender.state == .on
    }

    @objc func toggleRepeatedMaximizeRestoresPrevious(_ sender: NSButton) {
        Defaults.repeatedMaximizeRestoresPrevious.enabled = sender.state == .on
    }

    @IBAction func toggleTodoMode(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.todo.enabled = newSetting
        showHideTodoModeSettings(animated: true)
        Notification.Name.todoMenuToggled.post()
    }
    
    @IBAction func showTodoModeHelp(_ sender: Any) {
        if aboutTodoWindowController == nil {
            aboutTodoWindowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "AboutTodoWindowController") as? NSWindowController
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutTodoWindowController?.showWindow(self)
    }
    
    @IBAction func setTodoWidthUnit(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        guard let unit = TodoSidebarWidthUnit(rawValue: tag) else {
            Logger.log("Expected a pop up button to have a selected item with a valid tag matching a value of TodoSidebarWidthUnit. Got: \(String(describing: tag))")
            return
        }
        Defaults.todoSidebarWidthUnit.value = unit
        
        TodoManager.refreshTodoScreen()
        
        TodoManager.changeSidebarWidthUnit(to: unit)

        todoAppWidthField.stringValue = "\(Defaults.todoSidebarWidth.value)"

        TodoManager.moveAllIfNeeded(false)
    }
    
    @IBAction func setTodoAppSide(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        guard let side = TodoSidebarSide(rawValue: tag) else {
            Logger.log("Expected a pop up button to have a selected item with a valid tag matching a value of TodoSidebarSide. Got: \(String(describing: tag))")
            return
        }

        Defaults.todoSidebarSide.value = side
        
        TodoManager.moveAllIfNeeded(false)
    }
    
    @IBAction func stageSliderChanged(_ sender: NSSlider) {
        stageLabel.stringValue = "\(sender.intValue) px"
        if let event = NSApp.currentEvent {
            if event.type == .leftMouseUp || event.type == .keyDown {
                let value: Float = sender.floatValue == 0 ? -1 : sender.floatValue
                if value != Defaults.stageSize.value {
                    Defaults.stageSize.value = value
                }
            }
        }
    }
    
    @IBAction func restoreDefaults(_ sender: Any) {
        // Ask user if they want to restore to Rectangle or Spectacle defaults
        let currentDefaults = Defaults.alternateDefaultShortcuts.enabled ? "Rectangle" : "Spectacle"
        let defaultShortcutsTitle = NSLocalizedString("Default Shortcuts", tableName: "Main", value: "", comment: "")
        let currentlyUsingText = NSLocalizedString("Currently using: ", tableName: "Main", value: "", comment: "")
        let cancelText = NSLocalizedString("Cancel", tableName: "Main", value: "", comment: "")
        let response = AlertUtil.threeButtonAlert(question: defaultShortcutsTitle, text: currentlyUsingText + currentDefaults, buttonOneText: "Rectangle", buttonTwoText: "Spectacle", buttonThreeText: cancelText)
        if response == .alertThirdButtonReturn { return }

        //  Restore default shortcuts
        let rectangleDefaults = response == .alertFirstButtonReturn
        WindowAction.active.forEach { UserDefaults.standard.removeObject(forKey: $0.name) }
        Defaults.alternateDefaultShortcuts.enabled = rectangleDefaults
        Notification.Name.changeDefaults.post()
        
        // Restore snap areas
        Defaults.portraitSnapAreas.typedValue = nil
        Defaults.landscapeSnapAreas.typedValue = nil
        Notification.Name.defaultSnapAreas.post()
    }
    
    @IBAction func exportConfig(_ sender: NSButton) {
        Notification.Name.windowSnapping.post(object: false)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "RectangleConfig"
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            do {
                if let jsonString = Defaults.encoded() {
                    try jsonString.write(to: url, atomically: false, encoding: .utf8)
                }
            }
            catch {
                Logger.log(error.localizedDescription)
            }
        }
        Notification.Name.windowSnapping.post(object: true)
    }
    
    @IBAction func importConfig(_ sender: NSButton) {
        Notification.Name.windowSnapping.post(object: false)
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        let response = openPanel.runModal()
        if response == .OK, let url = openPanel.url {
            Defaults.load(fileUrl: url)
        }
        Notification.Name.windowSnapping.post(object: true)
    }

    @IBAction func showExtraSettings(_ sender: NSButton) {
        showExtraSettingsPopover(sender)
    }
    
    override func awakeFromNib() {
        initializeToggles()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stackBadgeChanged),
                                               name: .stackBadgeChanged,
                                               object: nil)

        checkForUpdatesAutomaticallyCheckbox.bind(.value, to: AppDelegate.instance.updaterController.updater, withKeyPath: "automaticallyChecksForUpdates", options: nil)
        
        let appVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        
        versionLabel.stringValue = "v" + appVersionString + " (" + buildString + ")"

        updateCheckForUpdatesTitle()
        
        initializeTodoModeSettings()
        shortcutRecordingObserver.observe([toggleTodoShortcutView, reflowTodoShortcutView])
        
        cycleSizesView.arrangedSubviews.forEach { view in
            cycleSizesView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        let cycleSizeCheckboxes = makeCycleSizeCheckboxes()
        self.cycleSizeCheckboxes = cycleSizeCheckboxes

        let cornerCycleExpansionAxisRow = makeCornerCycleExpansionAxisRow()
        let cooperativeCornerResizeCheckbox = makeCooperativeCornerResizeCheckbox()
        self.cooperativeCornerResizeCheckbox = cooperativeCornerResizeCheckbox
        cycleSizesView.orientation = .vertical
        cycleSizesView.alignment = .leading
        cycleSizesView.spacing = 8
        cycleSizesView.addArrangedSubview(makeCycleSizesRow(cycleSizeCheckboxes))
        cycleSizesView.addArrangedSubview(cornerCycleExpansionAxisRow)
        
        // Holding off on showing the cooperative resize feature for now
        if Defaults.cooperativeCornerResize.enabled {
            cycleSizesView.addArrangedSubview(cooperativeCornerResizeCheckbox)
        }
        
        initializeCycleSizesView(animated: false)

        initializeCombinedDisplayCheckbox()

        initializeGreenButtonOverrideCheckbox()

        initializeAutoMaximizeCheckbox()

        Notification.Name.configImported.onPost(using: {_ in
            self.initializeTodoModeSettings()
            self.initializeToggles()
            self.initializeCycleSizesView(animated: false)
        })
        
        Notification.Name.menuBarIconHidden.onPost(using: {_ in
            self.hideMenuBarIconCheckbox.state = .on
        })
        
        Notification.Name.updateAvailability.onPost { _ in
            self.updateCheckForUpdatesTitle()
        }
    }
    
    func updateCheckForUpdatesTitle() {
        checkForUpdatesButton.title = AppDelegate.instance.hasPendingUpdate ? "Update Available…".localized : "Check for Updates…".localized(key: "74m-kw-w1f.title")
    }
    
    func initializeTodoModeSettings() {
        todoCheckbox.state = Defaults.todo.userEnabled ? .on : .off
        todoAppWidthField.stringValue = String(Defaults.todoSidebarWidth.value)
        todoAppWidthField.delegate = self
        todoAppWidthField.defaults = Defaults.todoSidebarWidth
        todoAppWidthField.defaultsSetAction = {
            TodoManager.moveAllIfNeeded(false)
        }
        todoAppWidthUnitPopUpButton.selectItem(withTag: Defaults.todoSidebarWidthUnit.value.rawValue)
        todoAppSidePopUpButton.selectItem(withTag: Defaults.todoSidebarSide.value.rawValue)
        TodoManager.initToggleShortcut()
        TodoManager.initReflowShortcut()
        toggleTodoShortcutView.shortcutValidator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey)
        reflowTodoShortcutView.shortcutValidator = TodoShortcutValidator(defaultsKey: TodoManager.reflowDefaultsKey)
        toggleTodoShortcutView.setAssociatedUserDefaultsKey(TodoManager.toggleDefaultsKey, withTransformerName: MASDictionaryTransformerName)
        reflowTodoShortcutView.setAssociatedUserDefaultsKey(TodoManager.reflowDefaultsKey, withTransformerName: MASDictionaryTransformerName)
        showHideTodoModeSettings(animated: false)
    }
    
    private func showHideTodoModeSettings(animated: Bool) {
        setVisibility(shown: Defaults.todo.userEnabled, ofView: todoView, withConstraint: todoViewHeightConstraint, animated: animated)
    }
    
    func initializeToggles() {
        checkForUpdatesAutomaticallyCheckbox.state = Defaults.SUEnableAutomaticChecks.enabled ? .on : .off
        
        launchOnLoginCheckbox.state = Defaults.launchOnLogin.enabled ? .on : .off
        
        hideMenuBarIconCheckbox.state = Defaults.hideMenuBarIcon.enabled ? .on : .off
        
        subsequentExecutionPopUpButton.selectItem(withTag: Defaults.subsequentExecutionMode.value.rawValue)
        tileGridLimitRows.forEach { $0.reload() }
        
        allowAnyShortcutCheckbox.state = Defaults.allowAnyShortcut.enabled ? .on : .off
                
        gapSlider.intValue = Int32(Defaults.gapSize.value)
        gapLabel.stringValue = "\(gapSlider.intValue) px"
        gapSlider.isContinuous = true
        skipGapTopEdgeCheckbox.state = Defaults.skipGapTopEdge.enabled ? .on : .off
        skipGapTopEdgeCheckbox.isHidden = Defaults.gapSize.value == 0
        
        cursorAcrossCheckbox.state = Defaults.moveCursorAcrossDisplays.userEnabled ? .on : .off

        useCursorScreenDetectionCheckbox.isHidden = !Defaults.useCursorScreenDetection.enabled
        useCursorScreenDetectionCheckbox.state = Defaults.useCursorScreenDetection.enabled ? .on : .off

        doubleClickTitleBarCheckbox.state = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil ? .on : .off

        combinedDisplayModeCheckbox?.state = Defaults.combinedDisplayMode.userEnabled ? .on : .off

        greenButtonOverrideCheckbox?.state = Defaults.greenButtonOverride.enabled ? .on : .off

        autoMaximizeCheckbox?.state = Defaults.autoMaximize.userDisabled ? .off : .on

        halvesPreserveOtherAxisSizeCheckbox?.state = Defaults.halvesPreserveOtherAxisSize.enabled ? .on : .off
        repeatedMaximizeRestoresPreviousCheckbox?.state = Defaults.repeatedMaximizeRestoresPrevious.enabled ? .on : .off

        if StageUtil.stageCapable {
            stageSlider.intValue = Int32(Defaults.stageSize.value)
            stageSlider.isContinuous = true
            stageLabel.stringValue = "\(stageSlider.intValue) px"
        } else {
            stageView.isHidden = true
        }
        setToggleStatesForCycleSizeCheckboxes()
        setToggleStatesForCornerCycleExpansionAxisButtons()
        setToggleStateForCooperativeCornerResizeCheckbox()
    }
    
    private func initializeCycleSizesView(animated: Bool = false) {
        let showOptionsView = Defaults.subsequentExecutionMode.resizes
        
        if showOptionsView {
            setToggleStatesForCycleSizeCheckboxes()
            setToggleStatesForCornerCycleExpansionAxisButtons()
            setToggleStateForCooperativeCornerResizeCheckbox()
        }
        
        setVisibility(shown: showOptionsView, ofView: cycleSizesView, withConstraint: cycleSizesViewHeightConstraint, animated: animated)
    }
    
    private func initializeCombinedDisplayCheckbox() {
        if combinedDisplayModeCheckbox == nil, !NSScreen.screensHaveSeparateSpaces,
           let parentStack = doubleClickTitleBarCheckbox.superview as? NSStackView,
           let insertIdx = parentStack.arrangedSubviews.firstIndex(of: doubleClickTitleBarCheckbox) {
            
            let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Treat multiple displays as one", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleCombinedDisplayMode(_:)))
            checkbox.state = Defaults.combinedDisplayMode.userEnabled ? .on : .off
            // Match storyboard checkbox content priorities to prevent vertical compression
            checkbox.setContentCompressionResistancePriority(.required, for: .vertical)
            checkbox.setContentHuggingPriority(.defaultHigh, for: .vertical)
            
            // Must be set before inserting: NSStackView queries intrinsicContentSize once on
            // insertion, so preferredMaxLayoutWidth=0 would give zero height permanently.
            let descLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("When using multiple displays, treats them as a single display. Requires System Settings > Desktop & Dock > Displays have separate Spaces to be OFF.", tableName: "Main", value: "", comment: ""))
            descLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            descLabel.textColor = .secondaryLabelColor
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.preferredMaxLayoutWidth = 500
            descLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            descLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
            
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.setContentHuggingPriority(.defaultHigh, for: .vertical)
            
            parentStack.insertArrangedSubview(separator, at: insertIdx + 1)
            parentStack.insertArrangedSubview(checkbox, at: insertIdx + 2)
            parentStack.insertArrangedSubview(descLabel, at: insertIdx + 3)
            separator.widthAnchor.constraint(equalTo: doubleClickTitleBarCheckbox.widthAnchor).isActive = true
            separator.heightAnchor.constraint(equalToConstant: 20).isActive = true
            combinedDisplayModeCheckbox = checkbox
        }
    }

    private func initializeGreenButtonOverrideCheckbox() {
        if greenButtonOverrideCheckbox == nil,
           let parentStack = doubleClickTitleBarCheckbox.superview as? NSStackView,
           let insertIdx = parentStack.arrangedSubviews.firstIndex(of: doubleClickTitleBarCheckbox) {

            let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Green stoplight button maximizes instead of Full Screen", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleGreenButtonOverride(_:)))
            checkbox.state = Defaults.greenButtonOverride.enabled ? .on : .off
            // Match storyboard checkbox content priorities to prevent vertical compression
            checkbox.setContentCompressionResistancePriority(.required, for: .vertical)
            checkbox.setContentHuggingPriority(.defaultHigh, for: .vertical)

            // Must be set before inserting: NSStackView queries intrinsicContentSize once on
            // insertion, so preferredMaxLayoutWidth=0 would give zero height permanently.
            let descLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Hold any modifier key or use the window menu for default macOS behavior", tableName: "Main", value: "", comment: ""))
            descLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            descLabel.textColor = .secondaryLabelColor
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.preferredMaxLayoutWidth = 500
            descLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            descLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)

            parentStack.insertArrangedSubview(checkbox, at: insertIdx + 1)
            parentStack.insertArrangedSubview(descLabel, at: insertIdx + 2)
            greenButtonOverrideCheckbox = checkbox
        }
    }

    private func initializeAutoMaximizeCheckbox() {
        if autoMaximizeCheckbox == nil,
           let parentStack = doubleClickTitleBarCheckbox.superview as? NSStackView,
           let insertIdx = parentStack.arrangedSubviews.firstIndex(of: doubleClickTitleBarCheckbox) {

            let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Preserve maximize state when moving across displays", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleAutoMaximize(_:)))
            checkbox.state = Defaults.autoMaximize.userDisabled ? .off : .on
            checkbox.setContentCompressionResistancePriority(.required, for: .vertical)
            checkbox.setContentHuggingPriority(.defaultHigh, for: .vertical)

            parentStack.insertArrangedSubview(checkbox, at: insertIdx + 1)
            autoMaximizeCheckbox = checkbox
        }
    }

    private func setVisibility(shown: Bool, ofView view: NSView, withConstraint constraint: NSLayoutConstraint, animated: Bool) {
        
        if shown {
            view.isHidden = false
            constraint.isActive = false
            animateChanges(animated: animated) {
                view.animator().alphaValue = 1
            }
        } else {
            animateChanges(animated: animated) {
                view.isHidden = true
                constraint.isActive = true
            }
            DispatchQueue.main.async {
                view.alphaValue = 0
            }
        }
    }
    
    private func animateChanges(animated: Bool, block: () -> Void) {
        if animated {
            view.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                
                block()
                view.layoutSubtreeIfNeeded()
            }, completionHandler: nil)
        } else {
            block()
        }
    }
    
    private func makeCycleSizeCheckboxes() -> [NSButton] {
        CycleSize.sortedSizes.map { division in
            let button = NSButton(checkboxWithTitle: division.title, target: self, action: #selector(didCheckCycleSizeCheckbox(sender:)))
            button.tag = division.rawValue
            button.refusesFirstResponder = true
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            return button
        }
    }

    private func makeCycleSizesRow(_ checkboxes: [NSButton]) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        checkboxes.forEach { row.addArrangedSubview($0) }
        return row
    }

    private func makeCornerCycleExpansionAxisRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let label = NSTextField(labelWithString: NSLocalizedString("Cyclic corner shortcuts expand:", tableName: "Main", value: "", comment: ""))
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(label)

        let horizontalButton = makeCornerCycleExpansionAxisButton(title: NSLocalizedString("horizontally", tableName: "Main", value: "", comment: ""), axis: .horizontal)
        let verticalButton = makeCornerCycleExpansionAxisButton(title: NSLocalizedString("vertically", tableName: "Main", value: "", comment: ""), axis: .vertical)
        cornerCycleExpansionAxisButtons = [horizontalButton, verticalButton]
        cornerCycleExpansionAxisButtons.forEach { row.addArrangedSubview($0) }

        return row
    }

    private func makeCornerCycleExpansionAxisButton(title: String, axis: CornerCycleExpansionAxis) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(setCornerCycleExpansionAxis(_:)))
        button.tag = axis.rawValue
        button.refusesFirstResponder = true
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        return button
    }

    private func makeCooperativeCornerResizeCheckbox() -> NSButton {
        let button = NSButton(checkboxWithTitle: NSLocalizedString("Resize adjacent windows when cycling side or corner shortcuts", tableName: "Main", value: "", comment: ""),
                              target: self,
                              action: #selector(toggleCooperativeCornerResize(_:)))
        button.refusesFirstResponder = true
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        return button
    }
    
    @objc private func didCheckCycleSizeCheckbox(sender: Any?) {
        guard let checkbox = sender as? NSButton else {
            Logger.log("Expected action to be sent from NSButton. Instead, sender is: \(String(describing: sender))")
            return
        }
        
        let rawValue = checkbox.tag
        
        guard let cycleSize = CycleSize(rawValue: rawValue) else {
            Logger.log("Expected tag of cycle size checkbox to match a value of CycleSize. Got: \(String(describing: rawValue))")
            return
        }
        
        // If selected cycle sizes has not been changed, write the defaults.
        if !Defaults.cycleSizesIsChanged.enabled {
            Defaults.selectedCycleSizes.value = CycleSize.defaultSizes
        }
        
        Defaults.cycleSizesIsChanged.enabled = true
        
        if checkbox.state == .on {
            Defaults.selectedCycleSizes.value.insert(cycleSize)
        } else {
            Defaults.selectedCycleSizes.value.remove(cycleSize)
        }
    }
    
    private func setToggleStatesForCycleSizeCheckboxes() {
        let useDefaultCycleSizes = !Defaults.cycleSizesIsChanged.enabled
        let cycleSizes = useDefaultCycleSizes ? CycleSize.defaultSizes : Defaults.selectedCycleSizes.value
        
        cycleSizeCheckboxes.forEach { checkbox in
            guard let cycleSizeForCheckbox = CycleSize(rawValue: checkbox.tag) else {
                return
            }
            
            let isChecked = cycleSizes.contains(cycleSizeForCheckbox)
            checkbox.state = isChecked ? .on : .off
            checkbox.isEnabled = true
        }
    }

    private func setToggleStatesForCornerCycleExpansionAxisButtons() {
        cornerCycleExpansionAxisButtons.forEach { button in
            button.state = button.tag == Defaults.cornerCycleExpansionAxis.value.rawValue ? .on : .off
        }
    }

    private func setToggleStateForCooperativeCornerResizeCheckbox() {
        cooperativeCornerResizeCheckbox?.state = Defaults.cooperativeCornerResize.enabled ? .on : .off
    }

    @objc private func stackBadgeChanged() {
        stackBadgeCheckbox?.state = Defaults.stackBadge.userEnabled ? .on : .off
    }

}

extension SettingsViewController {
    static func freshController() -> SettingsViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let identifier = "SettingsViewController"
        guard let viewController = storyboard.instantiateController(withIdentifier: identifier) as? SettingsViewController else {
            fatalError("Unable to find ViewController - Check Main.storyboard")
        }
        return viewController
    }
}

extension SettingsViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let sender = obj.object as? AutoSaveFloatField,
              let defaults: FloatDefault = sender.defaults else { return }

        Debounce<Float>.input(sender.floatValue, comparedAgainst: sender.floatValue) { floatValue in
            defaults.value = floatValue
            self.resetActiveSideSplitRatiosIfNeeded(for: defaults)
            sender.defaultsSetAction?()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let sender = obj.object as? AutoSaveFloatField,
              let defaults: FloatDefault = sender.defaults else { return }

        if sender.stringValue.isEmpty {
            let fallback = sender.fallbackValue
            sender.stringValue = "\(Int(fallback))"
            defaults.value = fallback
            resetActiveSideSplitRatiosIfNeeded(for: defaults)
            sender.defaultsSetAction?()
        }
    }

    private func resetActiveSideSplitRatiosIfNeeded(for defaults: FloatDefault) {
        guard defaults.key == Defaults.horizontalSplitRatio.key
            || defaults.key == Defaults.verticalSplitRatio.key
        else {
            return
        }

        ActiveSideSplitRatios.shared.resetAll()
    }
}

class AutoSaveFloatField: NSTextField {
    var defaults: FloatDefault?
    var defaultsSetAction: (() -> Void)?
    var fallbackValue: Float = 30
}

class HalfSplitRatioPopUpButton: NSPopUpButton {
    static let otherTag = -1
    
    var defaults: FloatDefault?
    weak var customField: AutoSaveFloatField?
    
    func selectCurrentValue() {
        guard let value = defaults?.value else {
            selectItem(withTag: Self.otherTag)
            customField?.isHidden = false
            return
        }
        
        if let cycleSize = CycleSize.matching(percentValue: value) {
            selectItem(withTag: cycleSize.rawValue)
            customField?.isHidden = true
        } else {
            selectItem(withTag: Self.otherTag)
            customField?.isHidden = false
        }
    }
}
