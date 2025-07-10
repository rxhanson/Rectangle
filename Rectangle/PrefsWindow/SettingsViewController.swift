//
//  SettingsViewController.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/24/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import ServiceManagement
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
    @IBOutlet weak var cursorAcrossCheckbox: NSButton!
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
    
    
    private var aboutTodoWindowController: NSWindowController?
    
    private var cycleSizeCheckboxes = [NSButton]()
    
    @IBAction func toggleLaunchOnLogin(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        if #available(macOS 13, *) {
            LaunchOnLogin.isEnabled = newSetting
        } else {
            let smLoginSuccess = SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, newSetting)
            if !smLoginSuccess {
                Logger.log("Unable to set launch at login preference. Attempting one more time.")
                SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, newSetting)
            }            
        }
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
    
    @IBAction func gapSliderChanged(_ sender: NSSlider) {
        gapLabel.stringValue = "\(sender.intValue) px"
        if let event = NSApp.currentEvent {
            if event.type == .leftMouseUp || event.type == .keyDown {
                if Float(sender.intValue) != Defaults.gapSize.value {
                    Defaults.gapSize.value = Float(sender.intValue)
                }
            }
        }
    }
    
    @IBAction func toggleCursorMove(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.moveCursorAcrossDisplays.enabled = newSetting
    }
    
    @IBAction func toggleAllowAnyShortcut(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.allowAnyShortcut.enabled = newSetting
        Notification.Name.allowAnyShortcut.post(object: newSetting)
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        AppDelegate.updaterController.checkForUpdates(sender)
    }
    
    @IBAction func toggleDoubleClickTitleBar(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        if newSetting && !TitleBarManager.systemSettingDisabled {
            
            var openSystemSettingsButtonName = NSLocalizedString("iWV-c2-BJD.title", tableName: "Main", value: "Open System Preferences", comment: "")
            
            if #available(macOS 13, *) {
                openSystemSettingsButtonName = NSLocalizedString(
                    "Open System Settings", tableName: "Main", value: "", comment: "")
            }

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
        
        let toPixels = (unit == .pixels)
        let newValue = TodoManager.convertWidth(Defaults.todoSidebarWidth.value, toPixels: toPixels)
        Defaults.todoSidebarWidth.value = newValue
        todoAppWidthField.stringValue = String(newValue)

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
        WindowAction.active.forEach { UserDefaults.standard.removeObject(forKey: $0.name) }
        let rectangleDefaults = response == .alertFirstButtonReturn
        if rectangleDefaults != Defaults.alternateDefaultShortcuts.enabled {
            Defaults.alternateDefaultShortcuts.enabled = rectangleDefaults
            Notification.Name.changeDefaults.post()
        }
        
        // Restore snap areas
        Defaults.portraitSnapAreas.typedValue = nil
        Defaults.landscapeSnapAreas.typedValue = nil
        Notification.Name.defaultSnapAreas.post()
    }
    
    @IBAction func exportConfig(_ sender: NSButton) {
        Notification.Name.windowSnapping.post(object: false)
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["json"]
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
        openPanel.allowedFileTypes = ["json"]
        let response = openPanel.runModal()
        if response == .OK, let url = openPanel.url {
            Defaults.load(fileUrl: url)
        }
        Notification.Name.windowSnapping.post(object: true)
    }
    
    override func awakeFromNib() {
        initializeToggles()

        checkForUpdatesAutomaticallyCheckbox.bind(.value, to: AppDelegate.updaterController.updater, withKeyPath: "automaticallyChecksForUpdates", options: nil)
        
        let appVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        
        versionLabel.stringValue = "v" + appVersionString + " (" + buildString + ")"

        checkForUpdatesButton.title = NSLocalizedString("HIK-3r-i7E.title", tableName: "Main", value: "Check for Updates…", comment: "")
        
        initializeTodoModeSettings()
        
        self.cycleSizeCheckboxes.forEach {
            $0.removeFromSuperview()
        }
        
        let cycleSizeCheckboxes = makeCycleSizeCheckboxes()
        cycleSizeCheckboxes.forEach { checkbox in
            cycleSizesView.addArrangedSubview(checkbox)
        }
        self.cycleSizeCheckboxes = cycleSizeCheckboxes
        
        initializeCycleSizesView(animated: false)
        
        Notification.Name.configImported.onPost(using: {_ in
            self.initializeTodoModeSettings()
            self.initializeToggles()
            self.initializeCycleSizesView(animated: false)
        })
        
        Notification.Name.menuBarIconHidden.onPost(using: {_ in
            self.hideMenuBarIconCheckbox.state = .on
        })
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
        toggleTodoShortcutView.setAssociatedUserDefaultsKey(TodoManager.toggleDefaultsKey, withTransformerName: MASDictionaryTransformerName)
        reflowTodoShortcutView.setAssociatedUserDefaultsKey(TodoManager.reflowDefaultsKey, withTransformerName: MASDictionaryTransformerName)
        showHideTodoModeSettings(animated: false)
    }
    
    private func showHideTodoModeSettings(animated: Bool) {
        animateChanges(animated: animated) {
            let isEnabled = Defaults.todo.userEnabled
            todoView.isHidden = !isEnabled
            todoViewHeightConstraint.isActive = !isEnabled
        }
    }
    
    func initializeToggles() {
        checkForUpdatesAutomaticallyCheckbox.state = Defaults.SUEnableAutomaticChecks.enabled ? .on : .off
        
        launchOnLoginCheckbox.state = Defaults.launchOnLogin.enabled ? .on : .off
        
        hideMenuBarIconCheckbox.state = Defaults.hideMenuBarIcon.enabled ? .on : .off
        
        subsequentExecutionPopUpButton.selectItem(withTag: Defaults.subsequentExecutionMode.value.rawValue)
        
        allowAnyShortcutCheckbox.state = Defaults.allowAnyShortcut.enabled ? .on : .off
                
        gapSlider.intValue = Int32(Defaults.gapSize.value)
        gapLabel.stringValue = "\(gapSlider.intValue) px"
        gapSlider.isContinuous = true
        
        cursorAcrossCheckbox.state = Defaults.moveCursorAcrossDisplays.userEnabled ? .on : .off
        
        doubleClickTitleBarCheckbox.state = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil ? .on : .off

        if StageUtil.stageCapable {
            stageSlider.intValue = Int32(Defaults.stageSize.value)
            stageSlider.isContinuous = true
            stageLabel.stringValue = "\(stageSlider.intValue) px"
        } else {
            stageView.isHidden = true
        }
        
        
        setToggleStatesForCycleSizeCheckboxes()
    }
    
    private func initializeCycleSizesView(animated: Bool = false) {
        let showOptionsView = Defaults.subsequentExecutionMode.resizes
        
        if showOptionsView {
            setToggleStatesForCycleSizeCheckboxes()
        }
        
        animateChanges(animated: animated) {
            cycleSizesView.isHidden = !showOptionsView
            cycleSizesViewHeightConstraint.isActive = !showOptionsView
        }
    }

    private func animateChanges(animated: Bool, block: () -> Void) {
        if animated {
            NSAnimationContext.runAnimationGroup({context in
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
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            return button
        }
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
            
            let isAlwaysEnabled = cycleSizeForCheckbox.isAlwaysEnabled
            let isChecked = isAlwaysEnabled || cycleSizes.contains(cycleSizeForCheckbox)
            checkbox.state = isChecked ? .on : .off
            
            // Show that the box cannot be unchecked.
            if isAlwaysEnabled {
                checkbox.isEnabled = false
            }
        }
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
            sender.defaultsSetAction?()
        }
    }
}

class AutoSaveFloatField: NSTextField {
    var defaults: FloatDefault?
    var defaultsSetAction: (() -> Void)?
}
