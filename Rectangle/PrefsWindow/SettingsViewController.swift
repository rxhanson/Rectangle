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
    private var extraSettingsPopover: NSPopover?
    
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

    @IBAction func toggleUseCursorScreenDetection(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.useCursorScreenDetection.enabled = newSetting
    }

    @IBAction func toggleAllowAnyShortcut(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.allowAnyShortcut.enabled = newSetting
        Notification.Name.allowAnyShortcut.post(object: newSetting)
    }
    
    @objc func toggleShowEighthsInMenu(_ sender: NSButton) {
        let enabled: Bool = sender.state == .on
        Defaults.showEighthsInMenu.enabled = enabled
    }

    private static var individualRowsKey = "individualRowsKey"
    private static var cyclingRowsKey = "cyclingRowsKey"
    private static var cyclingHintKey = "cyclingHintKey"

    @objc func toggleCyclingShortcuts(_ sender: NSButton) {
        let enabled = sender.state == .on
        Defaults.useCyclingShortcuts.enabled = enabled
        if let individualRows = objc_getAssociatedObject(sender, &SettingsViewController.individualRowsKey) as? [NSView] {
            individualRows.forEach { $0.isHidden = enabled }
        }
        if let cyclingRows = objc_getAssociatedObject(sender, &SettingsViewController.cyclingRowsKey) as? [NSView] {
            cyclingRows.forEach { $0.isHidden = !enabled }
        }
        if let hintLabel = objc_getAssociatedObject(sender, &SettingsViewController.cyclingHintKey) as? NSView {
            hintLabel.isHidden = !enabled
        }
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        AppDelegate.instance.updaterController?.checkForUpdates(sender)
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
        
        TodoManager.refreshTodoScreen()
        
        if let visibleFrameWidth = TodoManager.todoScreen?.visibleFrame.width {
            let newValue = TodoManager.convert(width: Defaults.todoSidebarWidth.cgFloat, toUnit: unit, visibleFrameWidth: visibleFrameWidth)
            Defaults.todoSidebarWidth.value = Float(newValue)
            todoAppWidthField.stringValue = "\(newValue)"
        }

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

    @IBAction func showExtraSettings(_ sender: NSButton) {
        if extraSettingsPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            let viewController = NSViewController()

            let mainStackView = NSStackView()
            mainStackView.orientation = .vertical
            mainStackView.alignment = .leading
            mainStackView.spacing = 5
            mainStackView.translatesAutoresizingMaskIntoConstraints = false

            let headerLabel = NSTextField(labelWithString: NSLocalizedString("Extra Shortcuts", tableName: "Main", value: "", comment: ""))
            headerLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            headerLabel.alignment = .center
            headerLabel.translatesAutoresizingMaskIntoConstraints = false

            let largerWidthLabel = NSTextField(labelWithString: NSLocalizedString("Larger Width", tableName: "Main", value: "", comment: ""))
            largerWidthLabel.alignment = .right
            let smallerWidthLabel = NSTextField(labelWithString: NSLocalizedString("Smaller Width", tableName: "Main", value: "", comment: ""))
            smallerWidthLabel.alignment = .right
            let widthStepLabel = NSTextField(labelWithString: NSLocalizedString("Width Step (px)", tableName: "Main", value: "", comment: ""))
            widthStepLabel.alignment = .right
            
            let topVerticalThirdLabel = NSTextField(labelWithString: NSLocalizedString("Top Third", tableName: "Main", value: "", comment: ""))
            topVerticalThirdLabel.alignment = .right
            let middleVerticalThirdLabel = NSTextField(labelWithString: NSLocalizedString("Middle Third", tableName: "Main", value: "", comment: ""))
            middleVerticalThirdLabel.alignment = .right
            let bottomVerticalThirdLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Third", tableName: "Main", value: "", comment: ""))
            bottomVerticalThirdLabel.alignment = .right
            let topVerticalTwoThirdsLabel = NSTextField(labelWithString: NSLocalizedString("Top Two Thirds", tableName: "Main", value: "", comment: ""))
            topVerticalTwoThirdsLabel.alignment = .right
            let bottomVerticalTwoThirdsLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Two Thirds", tableName: "Main", value: "", comment: ""))
            bottomVerticalTwoThirdsLabel.alignment = .right

            let topLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Left Eighth", tableName: "Main", value: "", comment: ""))
            topLeftEighthLabel.alignment = .right
            let topCenterLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Left Eighth", tableName: "Main", value: "", comment: ""))
            topCenterLeftEighthLabel.alignment = .right
            let topCenterRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Right Eighth", tableName: "Main", value: "", comment: ""))
            topCenterRightEighthLabel.alignment = .right
            let topRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Right Eighth", tableName: "Main", value: "", comment: ""))
            topRightEighthLabel.alignment = .right
            let bottomLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Left Eighth", tableName: "Main", value: "", comment: ""))
            bottomLeftEighthLabel.alignment = .right
            let bottomCenterLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Left Eighth", tableName: "Main", value: "", comment: ""))
            bottomCenterLeftEighthLabel.alignment = .right
            let bottomCenterRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Right Eighth", tableName: "Main", value: "", comment: ""))
            bottomCenterRightEighthLabel.alignment = .right
            let bottomRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Right Eighth", tableName: "Main", value: "", comment: ""))
            bottomRightEighthLabel.alignment = .right

            largerWidthLabel.translatesAutoresizingMaskIntoConstraints = false
            smallerWidthLabel.translatesAutoresizingMaskIntoConstraints = false
            widthStepLabel.translatesAutoresizingMaskIntoConstraints = false
            topVerticalThirdLabel.translatesAutoresizingMaskIntoConstraints = false
            middleVerticalThirdLabel.translatesAutoresizingMaskIntoConstraints = false
            bottomVerticalThirdLabel.translatesAutoresizingMaskIntoConstraints = false
            topVerticalTwoThirdsLabel.translatesAutoresizingMaskIntoConstraints = false
            bottomVerticalTwoThirdsLabel.translatesAutoresizingMaskIntoConstraints = false
            topLeftEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            topCenterLeftEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            topCenterRightEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            topRightEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            bottomLeftEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            bottomCenterLeftEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            bottomCenterRightEighthLabel.translatesAutoresizingMaskIntoConstraints = false
            bottomRightEighthLabel.translatesAutoresizingMaskIntoConstraints = false

            let largerWidthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let smallerWidthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            
            let topVerticalThirdShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let middleVerticalThirdShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomVerticalThirdShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topVerticalTwoThirdsShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomVerticalTwoThirdsShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))

            let topLeftEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topCenterLeftEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topCenterRightEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topRightEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomLeftEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomCenterLeftEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomCenterRightEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomRightEighthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))

            let widthStepField = AutoSaveFloatField(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            widthStepField.stringValue = String(Int(Defaults.widthStepSize.value))
            widthStepField.delegate = self
            widthStepField.defaults = Defaults.widthStepSize
            widthStepField.translatesAutoresizingMaskIntoConstraints = false
            widthStepField.refusesFirstResponder = true
            widthStepField.alignment = .right

            let integerFormatter = NumberFormatter()
            integerFormatter.allowsFloats = false
            integerFormatter.minimum = 1
            widthStepField.formatter = integerFormatter

            let splitRatioHeaderLabel = NSTextField(labelWithString: NSLocalizedString("Half Split Ratios", tableName: "Main", value: "", comment: ""))
            splitRatioHeaderLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            splitRatioHeaderLabel.alignment = .center
            splitRatioHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

            let hSplitLabel = NSTextField(labelWithString: NSLocalizedString("Horizontal (L/R, %)", tableName: "Main", value: "", comment: ""))
            hSplitLabel.alignment = .right
            hSplitLabel.translatesAutoresizingMaskIntoConstraints = false

            let vSplitLabel = NSTextField(labelWithString: NSLocalizedString("Vertical (T/B, %)", tableName: "Main", value: "", comment: ""))
            vSplitLabel.alignment = .right
            vSplitLabel.translatesAutoresizingMaskIntoConstraints = false

            let percentFormatter = NumberFormatter()
            percentFormatter.allowsFloats = false
            percentFormatter.minimum = 1
            percentFormatter.maximum = 99

            let hSplitField = AutoSaveFloatField(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            hSplitField.stringValue = String(Int(Defaults.horizontalSplitRatio.value))
            hSplitField.delegate = self
            hSplitField.defaults = Defaults.horizontalSplitRatio
            hSplitField.fallbackValue = 50
            hSplitField.translatesAutoresizingMaskIntoConstraints = false
            hSplitField.refusesFirstResponder = true
            hSplitField.alignment = .right
            hSplitField.formatter = percentFormatter

            let vSplitField = AutoSaveFloatField(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            vSplitField.stringValue = String(Int(Defaults.verticalSplitRatio.value))
            vSplitField.delegate = self
            vSplitField.defaults = Defaults.verticalSplitRatio
            vSplitField.fallbackValue = 50
            vSplitField.translatesAutoresizingMaskIntoConstraints = false
            vSplitField.refusesFirstResponder = true
            vSplitField.alignment = .right
            vSplitField.formatter = percentFormatter

            largerWidthShortcutView.setAssociatedUserDefaultsKey(WindowAction.largerWidth.name, withTransformerName: MASDictionaryTransformerName)
            smallerWidthShortcutView.setAssociatedUserDefaultsKey(WindowAction.smallerWidth.name, withTransformerName: MASDictionaryTransformerName)
            
            topVerticalThirdShortcutView.setAssociatedUserDefaultsKey(WindowAction.topVerticalThird.name, withTransformerName: MASDictionaryTransformerName)
            middleVerticalThirdShortcutView.setAssociatedUserDefaultsKey(WindowAction.middleVerticalThird.name, withTransformerName: MASDictionaryTransformerName)
            bottomVerticalThirdShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomVerticalThird.name, withTransformerName: MASDictionaryTransformerName)
            topVerticalTwoThirdsShortcutView.setAssociatedUserDefaultsKey(WindowAction.topVerticalTwoThirds.name, withTransformerName: MASDictionaryTransformerName)
            bottomVerticalTwoThirdsShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomVerticalTwoThirds.name, withTransformerName: MASDictionaryTransformerName)

            topLeftEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topLeftEighth.name, withTransformerName: MASDictionaryTransformerName)
            topCenterLeftEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topCenterLeftEighth.name, withTransformerName: MASDictionaryTransformerName)
            topCenterRightEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topCenterRightEighth.name, withTransformerName: MASDictionaryTransformerName)
            topRightEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topRightEighth.name, withTransformerName: MASDictionaryTransformerName)
            bottomLeftEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomLeftEighth.name, withTransformerName: MASDictionaryTransformerName)
            bottomCenterLeftEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomCenterLeftEighth.name, withTransformerName: MASDictionaryTransformerName)
            bottomCenterRightEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomCenterRightEighth.name, withTransformerName: MASDictionaryTransformerName)
            bottomRightEighthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomRightEighth.name, withTransformerName: MASDictionaryTransformerName)

            if Defaults.allowAnyShortcut.enabled {
                let passThroughValidator = PassthroughShortcutValidator()
                largerWidthShortcutView.shortcutValidator = passThroughValidator
                smallerWidthShortcutView.shortcutValidator = passThroughValidator
                topVerticalThirdShortcutView.shortcutValidator = passThroughValidator
                middleVerticalThirdShortcutView.shortcutValidator = passThroughValidator
                bottomVerticalThirdShortcutView.shortcutValidator = passThroughValidator
                topVerticalTwoThirdsShortcutView.shortcutValidator = passThroughValidator
                bottomVerticalTwoThirdsShortcutView.shortcutValidator = passThroughValidator
                topLeftEighthShortcutView.shortcutValidator = passThroughValidator
                topCenterLeftEighthShortcutView.shortcutValidator = passThroughValidator
                topCenterRightEighthShortcutView.shortcutValidator = passThroughValidator
                topRightEighthShortcutView.shortcutValidator = passThroughValidator
                bottomLeftEighthShortcutView.shortcutValidator = passThroughValidator
                bottomCenterLeftEighthShortcutView.shortcutValidator = passThroughValidator
                bottomCenterRightEighthShortcutView.shortcutValidator = passThroughValidator
                bottomRightEighthShortcutView.shortcutValidator = passThroughValidator
            }

            let largerWidthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            largerWidthIcon.image = WindowAction.largerWidth.image
            largerWidthIcon.image?.size = NSSize(width: 21, height: 14)

            let smallerWidthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            smallerWidthIcon.image = WindowAction.smallerWidth.image
            smallerWidthIcon.image?.size = NSSize(width: 21, height: 14)
            
            let topVerticalThirdIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topVerticalThirdIcon.image = WindowAction.topVerticalThird.image
            topVerticalThirdIcon.image?.size = NSSize(width: 21, height: 14)
            
            let middleVerticalThirdIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            middleVerticalThirdIcon.image = WindowAction.middleVerticalThird.image
            middleVerticalThirdIcon.image?.size = NSSize(width: 21, height: 14)
            
            let bottomVerticalThirdIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomVerticalThirdIcon.image = WindowAction.bottomVerticalThird.image
            bottomVerticalThirdIcon.image?.size = NSSize(width: 21, height: 14)
            
            let topVerticalTwoThirdsIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topVerticalTwoThirdsIcon.image = WindowAction.topVerticalTwoThirds.image
            topVerticalTwoThirdsIcon.image?.size = NSSize(width: 21, height: 14)
            
            let bottomVerticalTwoThirdsIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomVerticalTwoThirdsIcon.image = WindowAction.bottomVerticalTwoThirds.image
            bottomVerticalTwoThirdsIcon.image?.size = NSSize(width: 21, height: 14)

            let topLeftEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topLeftEighthIcon.image = WindowAction.topLeftEighth.image
            topLeftEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let topCenterLeftEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topCenterLeftEighthIcon.image = WindowAction.topCenterLeftEighth.image
            topCenterLeftEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let topCenterRightEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topCenterRightEighthIcon.image = WindowAction.topCenterRightEighth.image
            topCenterRightEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let topRightEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topRightEighthIcon.image = WindowAction.topRightEighth.image
            topRightEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let bottomLeftEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomLeftEighthIcon.image = WindowAction.bottomLeftEighth.image
            bottomLeftEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let bottomCenterLeftEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomCenterLeftEighthIcon.image = WindowAction.bottomCenterLeftEighth.image
            bottomCenterLeftEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let bottomCenterRightEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomCenterRightEighthIcon.image = WindowAction.bottomCenterRightEighth.image
            bottomCenterRightEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let bottomRightEighthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomRightEighthIcon.image = WindowAction.bottomRightEighth.image
            bottomRightEighthIcon.image?.size = NSSize(width: 21, height: 14)

            let largerWidthLabelStack = NSStackView()
            largerWidthLabelStack.orientation = .horizontal
            largerWidthLabelStack.alignment = .centerY
            largerWidthLabelStack.spacing = 8
            largerWidthLabelStack.addArrangedSubview(largerWidthLabel)
            largerWidthLabelStack.addArrangedSubview(largerWidthIcon)

            let smallerWidthLabelStack = NSStackView()
            smallerWidthLabelStack.orientation = .horizontal
            smallerWidthLabelStack.alignment = .centerY
            smallerWidthLabelStack.spacing = 8
            smallerWidthLabelStack.addArrangedSubview(smallerWidthLabel)
            smallerWidthLabelStack.addArrangedSubview(smallerWidthIcon)
            
            let topVerticalThirdLabelStack = NSStackView()
            topVerticalThirdLabelStack.orientation = .horizontal
            topVerticalThirdLabelStack.alignment = .centerY
            topVerticalThirdLabelStack.spacing = 8
            topVerticalThirdLabelStack.addArrangedSubview(topVerticalThirdLabel)
            topVerticalThirdLabelStack.addArrangedSubview(topVerticalThirdIcon)
            
            let middleVerticalThirdLabelStack = NSStackView()
            middleVerticalThirdLabelStack.orientation = .horizontal
            middleVerticalThirdLabelStack.alignment = .centerY
            middleVerticalThirdLabelStack.spacing = 8
            middleVerticalThirdLabelStack.addArrangedSubview(middleVerticalThirdLabel)
            middleVerticalThirdLabelStack.addArrangedSubview(middleVerticalThirdIcon)
            
            let bottomVerticalThirdLabelStack = NSStackView()
            bottomVerticalThirdLabelStack.orientation = .horizontal
            bottomVerticalThirdLabelStack.alignment = .centerY
            bottomVerticalThirdLabelStack.spacing = 8
            bottomVerticalThirdLabelStack.addArrangedSubview(bottomVerticalThirdLabel)
            bottomVerticalThirdLabelStack.addArrangedSubview(bottomVerticalThirdIcon)
            
            let topVerticalTwoThirdsLabelStack = NSStackView()
            topVerticalTwoThirdsLabelStack.orientation = .horizontal
            topVerticalTwoThirdsLabelStack.alignment = .centerY
            topVerticalTwoThirdsLabelStack.spacing = 8
            topVerticalTwoThirdsLabelStack.addArrangedSubview(topVerticalTwoThirdsLabel)
            topVerticalTwoThirdsLabelStack.addArrangedSubview(topVerticalTwoThirdsIcon)
            
            let bottomVerticalTwoThirdsLabelStack = NSStackView()
            bottomVerticalTwoThirdsLabelStack.orientation = .horizontal
            bottomVerticalTwoThirdsLabelStack.alignment = .centerY
            bottomVerticalTwoThirdsLabelStack.spacing = 8
            bottomVerticalTwoThirdsLabelStack.addArrangedSubview(bottomVerticalTwoThirdsLabel)
            bottomVerticalTwoThirdsLabelStack.addArrangedSubview(bottomVerticalTwoThirdsIcon)

            let topLeftEighthLabelStack = NSStackView()
            topLeftEighthLabelStack.orientation = .horizontal
            topLeftEighthLabelStack.alignment = .centerY
            topLeftEighthLabelStack.spacing = 8
            topLeftEighthLabelStack.addArrangedSubview(topLeftEighthLabel)
            topLeftEighthLabelStack.addArrangedSubview(topLeftEighthIcon)

            let topCenterLeftEighthLabelStack = NSStackView()
            topCenterLeftEighthLabelStack.orientation = .horizontal
            topCenterLeftEighthLabelStack.alignment = .centerY
            topCenterLeftEighthLabelStack.spacing = 8
            topCenterLeftEighthLabelStack.addArrangedSubview(topCenterLeftEighthLabel)
            topCenterLeftEighthLabelStack.addArrangedSubview(topCenterLeftEighthIcon)

            let topCenterRightEighthLabelStack = NSStackView()
            topCenterRightEighthLabelStack.orientation = .horizontal
            topCenterRightEighthLabelStack.alignment = .centerY
            topCenterRightEighthLabelStack.spacing = 8
            topCenterRightEighthLabelStack.addArrangedSubview(topCenterRightEighthLabel)
            topCenterRightEighthLabelStack.addArrangedSubview(topCenterRightEighthIcon)

            let topRightEighthLabelStack = NSStackView()
            topRightEighthLabelStack.orientation = .horizontal
            topRightEighthLabelStack.alignment = .centerY
            topRightEighthLabelStack.spacing = 8
            topRightEighthLabelStack.addArrangedSubview(topRightEighthLabel)
            topRightEighthLabelStack.addArrangedSubview(topRightEighthIcon)

            let bottomLeftEighthLabelStack = NSStackView()
            bottomLeftEighthLabelStack.orientation = .horizontal
            bottomLeftEighthLabelStack.alignment = .centerY
            bottomLeftEighthLabelStack.spacing = 8
            bottomLeftEighthLabelStack.addArrangedSubview(bottomLeftEighthLabel)
            bottomLeftEighthLabelStack.addArrangedSubview(bottomLeftEighthIcon)

            let bottomCenterLeftEighthLabelStack = NSStackView()
            bottomCenterLeftEighthLabelStack.orientation = .horizontal
            bottomCenterLeftEighthLabelStack.alignment = .centerY
            bottomCenterLeftEighthLabelStack.spacing = 8
            bottomCenterLeftEighthLabelStack.addArrangedSubview(bottomCenterLeftEighthLabel)
            bottomCenterLeftEighthLabelStack.addArrangedSubview(bottomCenterLeftEighthIcon)

            let bottomCenterRightEighthLabelStack = NSStackView()
            bottomCenterRightEighthLabelStack.orientation = .horizontal
            bottomCenterRightEighthLabelStack.alignment = .centerY
            bottomCenterRightEighthLabelStack.spacing = 8
            bottomCenterRightEighthLabelStack.addArrangedSubview(bottomCenterRightEighthLabel)
            bottomCenterRightEighthLabelStack.addArrangedSubview(bottomCenterRightEighthIcon)

            let bottomRightEighthLabelStack = NSStackView()
            bottomRightEighthLabelStack.orientation = .horizontal
            bottomRightEighthLabelStack.alignment = .centerY
            bottomRightEighthLabelStack.spacing = 8
            bottomRightEighthLabelStack.addArrangedSubview(bottomRightEighthLabel)
            bottomRightEighthLabelStack.addArrangedSubview(bottomRightEighthIcon)

            let largerWidthRow = NSStackView()
            largerWidthRow.orientation = .horizontal
            largerWidthRow.alignment = .centerY
            largerWidthRow.spacing = 18
            largerWidthRow.addArrangedSubview(largerWidthLabelStack)
            largerWidthRow.addArrangedSubview(largerWidthShortcutView)

            let smallerWidthRow = NSStackView()
            smallerWidthRow.orientation = .horizontal
            smallerWidthRow.alignment = .centerY
            smallerWidthRow.spacing = 18
            smallerWidthRow.addArrangedSubview(smallerWidthLabelStack)
            smallerWidthRow.addArrangedSubview(smallerWidthShortcutView)

            let widthStepRow = NSStackView()
            widthStepRow.orientation = .horizontal
            widthStepRow.alignment = .centerY
            widthStepRow.spacing = 18
            widthStepRow.addArrangedSubview(widthStepLabel)
            widthStepRow.addArrangedSubview(widthStepField)

            let hSplitRow = NSStackView()
            hSplitRow.orientation = .horizontal
            hSplitRow.alignment = .centerY
            hSplitRow.spacing = 18
            hSplitRow.addArrangedSubview(hSplitLabel)
            hSplitRow.addArrangedSubview(hSplitField)

            let vSplitRow = NSStackView()
            vSplitRow.orientation = .horizontal
            vSplitRow.alignment = .centerY
            vSplitRow.spacing = 18
            vSplitRow.addArrangedSubview(vSplitLabel)
            vSplitRow.addArrangedSubview(vSplitField)
            
            let topVerticalThirdRow = NSStackView()
            topVerticalThirdRow.orientation = .horizontal
            topVerticalThirdRow.alignment = .centerY
            topVerticalThirdRow.spacing = 18
            topVerticalThirdRow.addArrangedSubview(topVerticalThirdLabelStack)
            topVerticalThirdRow.addArrangedSubview(topVerticalThirdShortcutView)
            
            let middleVerticalThirdRow = NSStackView()
            middleVerticalThirdRow.orientation = .horizontal
            middleVerticalThirdRow.alignment = .centerY
            middleVerticalThirdRow.spacing = 18
            middleVerticalThirdRow.addArrangedSubview(middleVerticalThirdLabelStack)
            middleVerticalThirdRow.addArrangedSubview(middleVerticalThirdShortcutView)
            
            let bottomVerticalThirdRow = NSStackView()
            bottomVerticalThirdRow.orientation = .horizontal
            bottomVerticalThirdRow.alignment = .centerY
            bottomVerticalThirdRow.spacing = 18
            bottomVerticalThirdRow.addArrangedSubview(bottomVerticalThirdLabelStack)
            bottomVerticalThirdRow.addArrangedSubview(bottomVerticalThirdShortcutView)
            
            let topVerticalTwoThirdsRow = NSStackView()
            topVerticalTwoThirdsRow.orientation = .horizontal
            topVerticalTwoThirdsRow.alignment = .centerY
            topVerticalTwoThirdsRow.spacing = 18
            topVerticalTwoThirdsRow.addArrangedSubview(topVerticalTwoThirdsLabelStack)
            topVerticalTwoThirdsRow.addArrangedSubview(topVerticalTwoThirdsShortcutView)
            
            let bottomVerticalTwoThirdsRow = NSStackView()
            bottomVerticalTwoThirdsRow.orientation = .horizontal
            bottomVerticalTwoThirdsRow.alignment = .centerY
            bottomVerticalTwoThirdsRow.spacing = 18
            bottomVerticalTwoThirdsRow.addArrangedSubview(bottomVerticalTwoThirdsLabelStack)
            bottomVerticalTwoThirdsRow.addArrangedSubview(bottomVerticalTwoThirdsShortcutView)

            let topLeftEighthRow = NSStackView()
            topLeftEighthRow.orientation = .horizontal
            topLeftEighthRow.alignment = .centerY
            topLeftEighthRow.spacing = 18
            topLeftEighthRow.addArrangedSubview(topLeftEighthLabelStack)
            topLeftEighthRow.addArrangedSubview(topLeftEighthShortcutView)

            let topCenterLeftEighthRow = NSStackView()
            topCenterLeftEighthRow.orientation = .horizontal
            topCenterLeftEighthRow.alignment = .centerY
            topCenterLeftEighthRow.spacing = 18
            topCenterLeftEighthRow.addArrangedSubview(topCenterLeftEighthLabelStack)
            topCenterLeftEighthRow.addArrangedSubview(topCenterLeftEighthShortcutView)

            let topCenterRightEighthRow = NSStackView()
            topCenterRightEighthRow.orientation = .horizontal
            topCenterRightEighthRow.alignment = .centerY
            topCenterRightEighthRow.spacing = 18
            topCenterRightEighthRow.addArrangedSubview(topCenterRightEighthLabelStack)
            topCenterRightEighthRow.addArrangedSubview(topCenterRightEighthShortcutView)

            let topRightEighthRow = NSStackView()
            topRightEighthRow.orientation = .horizontal
            topRightEighthRow.alignment = .centerY
            topRightEighthRow.spacing = 18
            topRightEighthRow.addArrangedSubview(topRightEighthLabelStack)
            topRightEighthRow.addArrangedSubview(topRightEighthShortcutView)

            let bottomLeftEighthRow = NSStackView()
            bottomLeftEighthRow.orientation = .horizontal
            bottomLeftEighthRow.alignment = .centerY
            bottomLeftEighthRow.spacing = 18
            bottomLeftEighthRow.addArrangedSubview(bottomLeftEighthLabelStack)
            bottomLeftEighthRow.addArrangedSubview(bottomLeftEighthShortcutView)

            let bottomCenterLeftEighthRow = NSStackView()
            bottomCenterLeftEighthRow.orientation = .horizontal
            bottomCenterLeftEighthRow.alignment = .centerY
            bottomCenterLeftEighthRow.spacing = 18
            bottomCenterLeftEighthRow.addArrangedSubview(bottomCenterLeftEighthLabelStack)
            bottomCenterLeftEighthRow.addArrangedSubview(bottomCenterLeftEighthShortcutView)

            let bottomCenterRightEighthRow = NSStackView()
            bottomCenterRightEighthRow.orientation = .horizontal
            bottomCenterRightEighthRow.alignment = .centerY
            bottomCenterRightEighthRow.spacing = 18
            bottomCenterRightEighthRow.addArrangedSubview(bottomCenterRightEighthLabelStack)
            bottomCenterRightEighthRow.addArrangedSubview(bottomCenterRightEighthShortcutView)

            let bottomRightEighthRow = NSStackView()
            bottomRightEighthRow.orientation = .horizontal
            bottomRightEighthRow.alignment = .centerY
            bottomRightEighthRow.spacing = 18
            bottomRightEighthRow.addArrangedSubview(bottomRightEighthLabelStack)
            bottomRightEighthRow.addArrangedSubview(bottomRightEighthShortcutView)

            mainStackView.addArrangedSubview(headerLabel)
            mainStackView.setCustomSpacing(10, after: headerLabel)
            mainStackView.addArrangedSubview(largerWidthRow)
            mainStackView.addArrangedSubview(smallerWidthRow)
            mainStackView.addArrangedSubview(widthStepRow)
            mainStackView.addArrangedSubview(topVerticalThirdRow)
            mainStackView.addArrangedSubview(middleVerticalThirdRow)
            mainStackView.addArrangedSubview(bottomVerticalThirdRow)
            mainStackView.addArrangedSubview(topVerticalTwoThirdsRow)
            mainStackView.addArrangedSubview(bottomVerticalTwoThirdsRow)
            mainStackView.addArrangedSubview(topLeftEighthRow)
            mainStackView.addArrangedSubview(topCenterLeftEighthRow)
            mainStackView.addArrangedSubview(topCenterRightEighthRow)
            mainStackView.addArrangedSubview(topRightEighthRow)
            mainStackView.addArrangedSubview(bottomLeftEighthRow)
            mainStackView.addArrangedSubview(bottomCenterLeftEighthRow)
            mainStackView.addArrangedSubview(bottomCenterRightEighthRow)
            mainStackView.addArrangedSubview(bottomRightEighthRow)
                        
            let showEighthsCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Show Eighths in menu", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleShowEighthsInMenu(_:)))
            showEighthsCheckbox.state = Defaults.showEighthsInMenu.userEnabled ? .on : .off
            showEighthsCheckbox.translatesAutoresizingMaskIntoConstraints = false
            showEighthsCheckbox.alignment = .right
            showEighthsCheckbox.imageHugsTitle = true

            mainStackView.addArrangedSubview(showEighthsCheckbox)

            // Grid Positions section
            let gridHeaderLabel = NSTextField(labelWithString: NSLocalizedString("Grid Positions", tableName: "Main", value: "", comment: ""))
            gridHeaderLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            gridHeaderLabel.alignment = .center
            gridHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

            let cyclingCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Use cycling shortcuts", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleCyclingShortcuts(_:)))
            cyclingCheckbox.state = Defaults.useCyclingShortcuts.enabled ? .on : .off
            cyclingCheckbox.translatesAutoresizingMaskIntoConstraints = false
            cyclingCheckbox.imageHugsTitle = true

            let cyclingHintLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Press the shortcut repeatedly to cycle through all positions in the grid.", tableName: "Main", value: "", comment: ""))
            cyclingHintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            cyclingHintLabel.textColor = .secondaryLabelColor
            cyclingHintLabel.alignment = .center
            cyclingHintLabel.translatesAutoresizingMaskIntoConstraints = false
            cyclingHintLabel.isHidden = !Defaults.useCyclingShortcuts.enabled

            // Individual twelfths rows
            let topLeftTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Top Left Twelfth", tableName: "Main", value: "", comment: ""))
            topLeftTwelfthLabel.alignment = .right
            topLeftTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let topCenterLeftTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Left Twelfth", tableName: "Main", value: "", comment: ""))
            topCenterLeftTwelfthLabel.alignment = .right
            topCenterLeftTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let topCenterRightTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Right Twelfth", tableName: "Main", value: "", comment: ""))
            topCenterRightTwelfthLabel.alignment = .right
            topCenterRightTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let topRightTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Top Right Twelfth", tableName: "Main", value: "", comment: ""))
            topRightTwelfthLabel.alignment = .right
            topRightTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let middleLeftTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Middle Left Twelfth", tableName: "Main", value: "", comment: ""))
            middleLeftTwelfthLabel.alignment = .right
            middleLeftTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let middleCenterLeftTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Middle Center Left Twelfth", tableName: "Main", value: "", comment: ""))
            middleCenterLeftTwelfthLabel.alignment = .right
            middleCenterLeftTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let middleCenterRightTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Middle Center Right Twelfth", tableName: "Main", value: "", comment: ""))
            middleCenterRightTwelfthLabel.alignment = .right
            middleCenterRightTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let middleRightTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Middle Right Twelfth", tableName: "Main", value: "", comment: ""))
            middleRightTwelfthLabel.alignment = .right
            middleRightTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomLeftTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Left Twelfth", tableName: "Main", value: "", comment: ""))
            bottomLeftTwelfthLabel.alignment = .right
            bottomLeftTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomCenterLeftTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Left Twelfth", tableName: "Main", value: "", comment: ""))
            bottomCenterLeftTwelfthLabel.alignment = .right
            bottomCenterLeftTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomCenterRightTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Right Twelfth", tableName: "Main", value: "", comment: ""))
            bottomCenterRightTwelfthLabel.alignment = .right
            bottomCenterRightTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomRightTwelfthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Right Twelfth", tableName: "Main", value: "", comment: ""))
            bottomRightTwelfthLabel.alignment = .right
            bottomRightTwelfthLabel.translatesAutoresizingMaskIntoConstraints = false

            let topLeftTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topCenterLeftTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topCenterRightTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topRightTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let middleLeftTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let middleCenterLeftTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let middleCenterRightTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let middleRightTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomLeftTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomCenterLeftTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomCenterRightTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomRightTwelfthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))

            topLeftTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            topCenterLeftTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topCenterLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            topCenterRightTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topCenterRightTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            topRightTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topRightTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            middleLeftTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.middleLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            middleCenterLeftTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.middleCenterLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            middleCenterRightTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.middleCenterRightTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            middleRightTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.middleRightTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            bottomLeftTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            bottomCenterLeftTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomCenterLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            bottomCenterRightTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomCenterRightTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            bottomRightTwelfthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomRightTwelfth.name, withTransformerName: MASDictionaryTransformerName)

            let topLeftTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topLeftTwelfthIcon.image = WindowAction.topLeftTwelfth.image
            topLeftTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let topCenterLeftTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topCenterLeftTwelfthIcon.image = WindowAction.topCenterLeftTwelfth.image
            topCenterLeftTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let topCenterRightTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topCenterRightTwelfthIcon.image = WindowAction.topCenterRightTwelfth.image
            topCenterRightTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let topRightTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topRightTwelfthIcon.image = WindowAction.topRightTwelfth.image
            topRightTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let middleLeftTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            middleLeftTwelfthIcon.image = WindowAction.middleLeftTwelfth.image
            middleLeftTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let middleCenterLeftTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            middleCenterLeftTwelfthIcon.image = WindowAction.middleCenterLeftTwelfth.image
            middleCenterLeftTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let middleCenterRightTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            middleCenterRightTwelfthIcon.image = WindowAction.middleCenterRightTwelfth.image
            middleCenterRightTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let middleRightTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            middleRightTwelfthIcon.image = WindowAction.middleRightTwelfth.image
            middleRightTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomLeftTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomLeftTwelfthIcon.image = WindowAction.bottomLeftTwelfth.image
            bottomLeftTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomCenterLeftTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomCenterLeftTwelfthIcon.image = WindowAction.bottomCenterLeftTwelfth.image
            bottomCenterLeftTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomCenterRightTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomCenterRightTwelfthIcon.image = WindowAction.bottomCenterRightTwelfth.image
            bottomCenterRightTwelfthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomRightTwelfthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomRightTwelfthIcon.image = WindowAction.bottomRightTwelfth.image
            bottomRightTwelfthIcon.image?.size = NSSize(width: 21, height: 14)

            func makeLabelStack(_ label: NSTextField, _ icon: NSImageView) -> NSStackView {
                let stack = NSStackView()
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 8
                stack.addArrangedSubview(label)
                stack.addArrangedSubview(icon)
                return stack
            }

            func makeRow(_ labelStack: NSStackView, _ shortcutView: MASShortcutView) -> NSStackView {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 18
                row.addArrangedSubview(labelStack)
                row.addArrangedSubview(shortcutView)
                return row
            }

            let topLeftTwelfthRow = makeRow(makeLabelStack(topLeftTwelfthLabel, topLeftTwelfthIcon), topLeftTwelfthShortcutView)
            let topCenterLeftTwelfthRow = makeRow(makeLabelStack(topCenterLeftTwelfthLabel, topCenterLeftTwelfthIcon), topCenterLeftTwelfthShortcutView)
            let topCenterRightTwelfthRow = makeRow(makeLabelStack(topCenterRightTwelfthLabel, topCenterRightTwelfthIcon), topCenterRightTwelfthShortcutView)
            let topRightTwelfthRow = makeRow(makeLabelStack(topRightTwelfthLabel, topRightTwelfthIcon), topRightTwelfthShortcutView)
            let middleLeftTwelfthRow = makeRow(makeLabelStack(middleLeftTwelfthLabel, middleLeftTwelfthIcon), middleLeftTwelfthShortcutView)
            let middleCenterLeftTwelfthRow = makeRow(makeLabelStack(middleCenterLeftTwelfthLabel, middleCenterLeftTwelfthIcon), middleCenterLeftTwelfthShortcutView)
            let middleCenterRightTwelfthRow = makeRow(makeLabelStack(middleCenterRightTwelfthLabel, middleCenterRightTwelfthIcon), middleCenterRightTwelfthShortcutView)
            let middleRightTwelfthRow = makeRow(makeLabelStack(middleRightTwelfthLabel, middleRightTwelfthIcon), middleRightTwelfthShortcutView)
            let bottomLeftTwelfthRow = makeRow(makeLabelStack(bottomLeftTwelfthLabel, bottomLeftTwelfthIcon), bottomLeftTwelfthShortcutView)
            let bottomCenterLeftTwelfthRow = makeRow(makeLabelStack(bottomCenterLeftTwelfthLabel, bottomCenterLeftTwelfthIcon), bottomCenterLeftTwelfthShortcutView)
            let bottomCenterRightTwelfthRow = makeRow(makeLabelStack(bottomCenterRightTwelfthLabel, bottomCenterRightTwelfthIcon), bottomCenterRightTwelfthShortcutView)
            let bottomRightTwelfthRow = makeRow(makeLabelStack(bottomRightTwelfthLabel, bottomRightTwelfthIcon), bottomRightTwelfthShortcutView)

            // Individual sixteenths rows
            let topLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Top Left Sixteenth", tableName: "Main", value: "", comment: ""))
            topLeftSixteenthLabel.alignment = .right
            topLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let topCenterLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Left Sixteenth", tableName: "Main", value: "", comment: ""))
            topCenterLeftSixteenthLabel.alignment = .right
            topCenterLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let topCenterRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Right Sixteenth", tableName: "Main", value: "", comment: ""))
            topCenterRightSixteenthLabel.alignment = .right
            topCenterRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let topRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Top Right Sixteenth", tableName: "Main", value: "", comment: ""))
            topRightSixteenthLabel.alignment = .right
            topRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let upperMiddleLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Upper Middle Left Sixteenth", tableName: "Main", value: "", comment: ""))
            upperMiddleLeftSixteenthLabel.alignment = .right
            upperMiddleLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let upperMiddleCenterLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Upper Middle Center Left Sixteenth", tableName: "Main", value: "", comment: ""))
            upperMiddleCenterLeftSixteenthLabel.alignment = .right
            upperMiddleCenterLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let upperMiddleCenterRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Upper Middle Center Right Sixteenth", tableName: "Main", value: "", comment: ""))
            upperMiddleCenterRightSixteenthLabel.alignment = .right
            upperMiddleCenterRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let upperMiddleRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Upper Middle Right Sixteenth", tableName: "Main", value: "", comment: ""))
            upperMiddleRightSixteenthLabel.alignment = .right
            upperMiddleRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let lowerMiddleLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Lower Middle Left Sixteenth", tableName: "Main", value: "", comment: ""))
            lowerMiddleLeftSixteenthLabel.alignment = .right
            lowerMiddleLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let lowerMiddleCenterLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Lower Middle Center Left Sixteenth", tableName: "Main", value: "", comment: ""))
            lowerMiddleCenterLeftSixteenthLabel.alignment = .right
            lowerMiddleCenterLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let lowerMiddleCenterRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Lower Middle Center Right Sixteenth", tableName: "Main", value: "", comment: ""))
            lowerMiddleCenterRightSixteenthLabel.alignment = .right
            lowerMiddleCenterRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let lowerMiddleRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Lower Middle Right Sixteenth", tableName: "Main", value: "", comment: ""))
            lowerMiddleRightSixteenthLabel.alignment = .right
            lowerMiddleRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Left Sixteenth", tableName: "Main", value: "", comment: ""))
            bottomLeftSixteenthLabel.alignment = .right
            bottomLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomCenterLeftSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Left Sixteenth", tableName: "Main", value: "", comment: ""))
            bottomCenterLeftSixteenthLabel.alignment = .right
            bottomCenterLeftSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomCenterRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Right Sixteenth", tableName: "Main", value: "", comment: ""))
            bottomCenterRightSixteenthLabel.alignment = .right
            bottomCenterRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false
            let bottomRightSixteenthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Right Sixteenth", tableName: "Main", value: "", comment: ""))
            bottomRightSixteenthLabel.alignment = .right
            bottomRightSixteenthLabel.translatesAutoresizingMaskIntoConstraints = false

            let topLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topCenterLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topCenterRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let topRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let upperMiddleLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let upperMiddleCenterLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let upperMiddleCenterRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let upperMiddleRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let lowerMiddleLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let lowerMiddleCenterLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let lowerMiddleCenterRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let lowerMiddleRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomCenterLeftSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomCenterRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let bottomRightSixteenthShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))

            topLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            topCenterLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topCenterLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            topCenterRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topCenterRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            topRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.topRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            upperMiddleLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.upperMiddleLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            upperMiddleCenterLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.upperMiddleCenterLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            upperMiddleCenterRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.upperMiddleCenterRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            upperMiddleRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.upperMiddleRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            lowerMiddleLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.lowerMiddleLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            lowerMiddleCenterLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.lowerMiddleCenterLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            lowerMiddleCenterRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.lowerMiddleCenterRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            lowerMiddleRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.lowerMiddleRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            bottomLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            bottomCenterLeftSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomCenterLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            bottomCenterRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomCenterRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)
            bottomRightSixteenthShortcutView.setAssociatedUserDefaultsKey(WindowAction.bottomRightSixteenth.name, withTransformerName: MASDictionaryTransformerName)

            let topLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topLeftSixteenthIcon.image = WindowAction.topLeftSixteenth.image
            topLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let topCenterLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topCenterLeftSixteenthIcon.image = WindowAction.topCenterLeftSixteenth.image
            topCenterLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let topCenterRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topCenterRightSixteenthIcon.image = WindowAction.topCenterRightSixteenth.image
            topCenterRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let topRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            topRightSixteenthIcon.image = WindowAction.topRightSixteenth.image
            topRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let upperMiddleLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            upperMiddleLeftSixteenthIcon.image = WindowAction.upperMiddleLeftSixteenth.image
            upperMiddleLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let upperMiddleCenterLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            upperMiddleCenterLeftSixteenthIcon.image = WindowAction.upperMiddleCenterLeftSixteenth.image
            upperMiddleCenterLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let upperMiddleCenterRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            upperMiddleCenterRightSixteenthIcon.image = WindowAction.upperMiddleCenterRightSixteenth.image
            upperMiddleCenterRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let upperMiddleRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            upperMiddleRightSixteenthIcon.image = WindowAction.upperMiddleRightSixteenth.image
            upperMiddleRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let lowerMiddleLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            lowerMiddleLeftSixteenthIcon.image = WindowAction.lowerMiddleLeftSixteenth.image
            lowerMiddleLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let lowerMiddleCenterLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            lowerMiddleCenterLeftSixteenthIcon.image = WindowAction.lowerMiddleCenterLeftSixteenth.image
            lowerMiddleCenterLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let lowerMiddleCenterRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            lowerMiddleCenterRightSixteenthIcon.image = WindowAction.lowerMiddleCenterRightSixteenth.image
            lowerMiddleCenterRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let lowerMiddleRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            lowerMiddleRightSixteenthIcon.image = WindowAction.lowerMiddleRightSixteenth.image
            lowerMiddleRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomLeftSixteenthIcon.image = WindowAction.bottomLeftSixteenth.image
            bottomLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomCenterLeftSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomCenterLeftSixteenthIcon.image = WindowAction.bottomCenterLeftSixteenth.image
            bottomCenterLeftSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomCenterRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomCenterRightSixteenthIcon.image = WindowAction.bottomCenterRightSixteenth.image
            bottomCenterRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)
            let bottomRightSixteenthIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            bottomRightSixteenthIcon.image = WindowAction.bottomRightSixteenth.image
            bottomRightSixteenthIcon.image?.size = NSSize(width: 21, height: 14)

            let topLeftSixteenthRow = makeRow(makeLabelStack(topLeftSixteenthLabel, topLeftSixteenthIcon), topLeftSixteenthShortcutView)
            let topCenterLeftSixteenthRow = makeRow(makeLabelStack(topCenterLeftSixteenthLabel, topCenterLeftSixteenthIcon), topCenterLeftSixteenthShortcutView)
            let topCenterRightSixteenthRow = makeRow(makeLabelStack(topCenterRightSixteenthLabel, topCenterRightSixteenthIcon), topCenterRightSixteenthShortcutView)
            let topRightSixteenthRow = makeRow(makeLabelStack(topRightSixteenthLabel, topRightSixteenthIcon), topRightSixteenthShortcutView)
            let upperMiddleLeftSixteenthRow = makeRow(makeLabelStack(upperMiddleLeftSixteenthLabel, upperMiddleLeftSixteenthIcon), upperMiddleLeftSixteenthShortcutView)
            let upperMiddleCenterLeftSixteenthRow = makeRow(makeLabelStack(upperMiddleCenterLeftSixteenthLabel, upperMiddleCenterLeftSixteenthIcon), upperMiddleCenterLeftSixteenthShortcutView)
            let upperMiddleCenterRightSixteenthRow = makeRow(makeLabelStack(upperMiddleCenterRightSixteenthLabel, upperMiddleCenterRightSixteenthIcon), upperMiddleCenterRightSixteenthShortcutView)
            let upperMiddleRightSixteenthRow = makeRow(makeLabelStack(upperMiddleRightSixteenthLabel, upperMiddleRightSixteenthIcon), upperMiddleRightSixteenthShortcutView)
            let lowerMiddleLeftSixteenthRow = makeRow(makeLabelStack(lowerMiddleLeftSixteenthLabel, lowerMiddleLeftSixteenthIcon), lowerMiddleLeftSixteenthShortcutView)
            let lowerMiddleCenterLeftSixteenthRow = makeRow(makeLabelStack(lowerMiddleCenterLeftSixteenthLabel, lowerMiddleCenterLeftSixteenthIcon), lowerMiddleCenterLeftSixteenthShortcutView)
            let lowerMiddleCenterRightSixteenthRow = makeRow(makeLabelStack(lowerMiddleCenterRightSixteenthLabel, lowerMiddleCenterRightSixteenthIcon), lowerMiddleCenterRightSixteenthShortcutView)
            let lowerMiddleRightSixteenthRow = makeRow(makeLabelStack(lowerMiddleRightSixteenthLabel, lowerMiddleRightSixteenthIcon), lowerMiddleRightSixteenthShortcutView)
            let bottomLeftSixteenthRow = makeRow(makeLabelStack(bottomLeftSixteenthLabel, bottomLeftSixteenthIcon), bottomLeftSixteenthShortcutView)
            let bottomCenterLeftSixteenthRow = makeRow(makeLabelStack(bottomCenterLeftSixteenthLabel, bottomCenterLeftSixteenthIcon), bottomCenterLeftSixteenthShortcutView)
            let bottomCenterRightSixteenthRow = makeRow(makeLabelStack(bottomCenterRightSixteenthLabel, bottomCenterRightSixteenthIcon), bottomCenterRightSixteenthShortcutView)
            let bottomRightSixteenthRow = makeRow(makeLabelStack(bottomRightSixteenthLabel, bottomRightSixteenthIcon), bottomRightSixteenthShortcutView)

            // Cycling rows - one per category (hidden by default, shown when cycling mode is on)
            let eighthsCyclingLabel = NSTextField(labelWithString: NSLocalizedString("Eighths (4\u{00d7}2)", tableName: "Main", value: "", comment: ""))
            eighthsCyclingLabel.alignment = .right
            eighthsCyclingLabel.translatesAutoresizingMaskIntoConstraints = false
            let twelfthsCyclingLabel = NSTextField(labelWithString: NSLocalizedString("Twelfths (4\u{00d7}3)", tableName: "Main", value: "", comment: ""))
            twelfthsCyclingLabel.alignment = .right
            twelfthsCyclingLabel.translatesAutoresizingMaskIntoConstraints = false
            let sixteenthsCyclingLabel = NSTextField(labelWithString: NSLocalizedString("Sixteenths (4\u{00d7}4)", tableName: "Main", value: "", comment: ""))
            sixteenthsCyclingLabel.alignment = .right
            sixteenthsCyclingLabel.translatesAutoresizingMaskIntoConstraints = false

            let eighthsCyclingShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let twelfthsCyclingShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            let sixteenthsCyclingShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))

            eighthsCyclingShortcutView.setAssociatedUserDefaultsKey(WindowAction.topLeftEighth.name, withTransformerName: MASDictionaryTransformerName)
            twelfthsCyclingShortcutView.setAssociatedUserDefaultsKey(WindowAction.topLeftTwelfth.name, withTransformerName: MASDictionaryTransformerName)
            sixteenthsCyclingShortcutView.setAssociatedUserDefaultsKey(WindowAction.topLeftSixteenth.name, withTransformerName: MASDictionaryTransformerName)

            let eighthsCyclingIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            eighthsCyclingIcon.image = WindowAction.topLeftEighth.image
            eighthsCyclingIcon.image?.size = NSSize(width: 21, height: 14)
            let twelfthsCyclingIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            twelfthsCyclingIcon.image = WindowAction.topLeftTwelfth.image
            twelfthsCyclingIcon.image?.size = NSSize(width: 21, height: 14)
            let sixteenthsCyclingIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            sixteenthsCyclingIcon.image = WindowAction.topLeftSixteenth.image
            sixteenthsCyclingIcon.image?.size = NSSize(width: 21, height: 14)

            let eighthsCyclingRow = makeRow(makeLabelStack(eighthsCyclingLabel, eighthsCyclingIcon), eighthsCyclingShortcutView)
            let twelfthsCyclingRow = makeRow(makeLabelStack(twelfthsCyclingLabel, twelfthsCyclingIcon), twelfthsCyclingShortcutView)
            let sixteenthsCyclingRow = makeRow(makeLabelStack(sixteenthsCyclingLabel, sixteenthsCyclingIcon), sixteenthsCyclingShortcutView)

            if Defaults.allowAnyShortcut.enabled {
                let passThroughValidator = PassthroughShortcutValidator()
                topLeftTwelfthShortcutView.shortcutValidator = passThroughValidator
                topCenterLeftTwelfthShortcutView.shortcutValidator = passThroughValidator
                topCenterRightTwelfthShortcutView.shortcutValidator = passThroughValidator
                topRightTwelfthShortcutView.shortcutValidator = passThroughValidator
                middleLeftTwelfthShortcutView.shortcutValidator = passThroughValidator
                middleCenterLeftTwelfthShortcutView.shortcutValidator = passThroughValidator
                middleCenterRightTwelfthShortcutView.shortcutValidator = passThroughValidator
                middleRightTwelfthShortcutView.shortcutValidator = passThroughValidator
                bottomLeftTwelfthShortcutView.shortcutValidator = passThroughValidator
                bottomCenterLeftTwelfthShortcutView.shortcutValidator = passThroughValidator
                bottomCenterRightTwelfthShortcutView.shortcutValidator = passThroughValidator
                bottomRightTwelfthShortcutView.shortcutValidator = passThroughValidator
                topLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                topCenterLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                topCenterRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                topRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                upperMiddleLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                upperMiddleCenterLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                upperMiddleCenterRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                upperMiddleRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                lowerMiddleLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                lowerMiddleCenterLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                lowerMiddleCenterRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                lowerMiddleRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                bottomLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                bottomCenterLeftSixteenthShortcutView.shortcutValidator = passThroughValidator
                bottomCenterRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                bottomRightSixteenthShortcutView.shortcutValidator = passThroughValidator
                eighthsCyclingShortcutView.shortcutValidator = passThroughValidator
                twelfthsCyclingShortcutView.shortcutValidator = passThroughValidator
                sixteenthsCyclingShortcutView.shortcutValidator = passThroughValidator
            }

            // Collect rows for toggling
            let individualGridRows: [NSView] = [
                topLeftTwelfthRow, topCenterLeftTwelfthRow, topCenterRightTwelfthRow, topRightTwelfthRow,
                middleLeftTwelfthRow, middleCenterLeftTwelfthRow, middleCenterRightTwelfthRow, middleRightTwelfthRow,
                bottomLeftTwelfthRow, bottomCenterLeftTwelfthRow, bottomCenterRightTwelfthRow, bottomRightTwelfthRow,
                topLeftSixteenthRow, topCenterLeftSixteenthRow, topCenterRightSixteenthRow, topRightSixteenthRow,
                upperMiddleLeftSixteenthRow, upperMiddleCenterLeftSixteenthRow, upperMiddleCenterRightSixteenthRow, upperMiddleRightSixteenthRow,
                lowerMiddleLeftSixteenthRow, lowerMiddleCenterLeftSixteenthRow, lowerMiddleCenterRightSixteenthRow, lowerMiddleRightSixteenthRow,
                bottomLeftSixteenthRow, bottomCenterLeftSixteenthRow, bottomCenterRightSixteenthRow, bottomRightSixteenthRow
            ]

            let cyclingGridRows: [NSView] = [eighthsCyclingRow, twelfthsCyclingRow, sixteenthsCyclingRow]

            let isCycling = Defaults.useCyclingShortcuts.enabled
            individualGridRows.forEach { $0.isHidden = isCycling }
            cyclingGridRows.forEach { $0.isHidden = !isCycling }

            // Assemble the grid section in main stack
            mainStackView.addArrangedSubview(gridHeaderLabel)
            mainStackView.setCustomSpacing(6, after: gridHeaderLabel)
            mainStackView.addArrangedSubview(cyclingCheckbox)
            mainStackView.setCustomSpacing(4, after: cyclingCheckbox)
            mainStackView.addArrangedSubview(cyclingHintLabel)
            mainStackView.setCustomSpacing(8, after: cyclingHintLabel)

            // Cycling rows
            mainStackView.addArrangedSubview(eighthsCyclingRow)
            mainStackView.addArrangedSubview(twelfthsCyclingRow)
            mainStackView.addArrangedSubview(sixteenthsCyclingRow)

            // Individual twelfths rows
            mainStackView.addArrangedSubview(topLeftTwelfthRow)
            mainStackView.addArrangedSubview(topCenterLeftTwelfthRow)
            mainStackView.addArrangedSubview(topCenterRightTwelfthRow)
            mainStackView.addArrangedSubview(topRightTwelfthRow)
            mainStackView.addArrangedSubview(middleLeftTwelfthRow)
            mainStackView.addArrangedSubview(middleCenterLeftTwelfthRow)
            mainStackView.addArrangedSubview(middleCenterRightTwelfthRow)
            mainStackView.addArrangedSubview(middleRightTwelfthRow)
            mainStackView.addArrangedSubview(bottomLeftTwelfthRow)
            mainStackView.addArrangedSubview(bottomCenterLeftTwelfthRow)
            mainStackView.addArrangedSubview(bottomCenterRightTwelfthRow)
            mainStackView.addArrangedSubview(bottomRightTwelfthRow)

            // Individual sixteenths rows
            mainStackView.addArrangedSubview(topLeftSixteenthRow)
            mainStackView.addArrangedSubview(topCenterLeftSixteenthRow)
            mainStackView.addArrangedSubview(topCenterRightSixteenthRow)
            mainStackView.addArrangedSubview(topRightSixteenthRow)
            mainStackView.addArrangedSubview(upperMiddleLeftSixteenthRow)
            mainStackView.addArrangedSubview(upperMiddleCenterLeftSixteenthRow)
            mainStackView.addArrangedSubview(upperMiddleCenterRightSixteenthRow)
            mainStackView.addArrangedSubview(upperMiddleRightSixteenthRow)
            mainStackView.addArrangedSubview(lowerMiddleLeftSixteenthRow)
            mainStackView.addArrangedSubview(lowerMiddleCenterLeftSixteenthRow)
            mainStackView.addArrangedSubview(lowerMiddleCenterRightSixteenthRow)
            mainStackView.addArrangedSubview(lowerMiddleRightSixteenthRow)
            mainStackView.addArrangedSubview(bottomLeftSixteenthRow)
            mainStackView.addArrangedSubview(bottomCenterLeftSixteenthRow)
            mainStackView.addArrangedSubview(bottomCenterRightSixteenthRow)
            mainStackView.addArrangedSubview(bottomRightSixteenthRow)

            // Store row references for toggling via tag on cyclingCheckbox
            cyclingCheckbox.tag = 0
            objc_setAssociatedObject(cyclingCheckbox, &SettingsViewController.individualRowsKey, individualGridRows, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            objc_setAssociatedObject(cyclingCheckbox, &SettingsViewController.cyclingRowsKey, cyclingGridRows, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            objc_setAssociatedObject(cyclingCheckbox, &SettingsViewController.cyclingHintKey, cyclingHintLabel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            mainStackView.addArrangedSubview(splitRatioHeaderLabel)
            mainStackView.setCustomSpacing(10, after: splitRatioHeaderLabel)
            mainStackView.addArrangedSubview(hSplitRow)
            mainStackView.addArrangedSubview(vSplitRow)

            NSLayoutConstraint.activate([
                headerLabel.widthAnchor.constraint(equalTo: mainStackView.widthAnchor),
                splitRatioHeaderLabel.widthAnchor.constraint(equalTo: mainStackView.widthAnchor),
                largerWidthLabel.widthAnchor.constraint(equalTo: smallerWidthLabel.widthAnchor),
                smallerWidthLabel.widthAnchor.constraint(equalTo: widthStepLabel.widthAnchor),
                widthStepLabel.widthAnchor.constraint(equalTo: topVerticalThirdLabel.widthAnchor),
                topVerticalThirdLabel.widthAnchor.constraint(equalTo: middleVerticalThirdLabel.widthAnchor),
                middleVerticalThirdLabel.widthAnchor.constraint(equalTo: bottomVerticalThirdLabel.widthAnchor),
                bottomVerticalThirdLabel.widthAnchor.constraint(equalTo: topVerticalTwoThirdsLabel.widthAnchor),
                topVerticalTwoThirdsLabel.widthAnchor.constraint(equalTo: bottomVerticalTwoThirdsLabel.widthAnchor),
                bottomVerticalTwoThirdsLabel.widthAnchor.constraint(equalTo: topLeftEighthLabel.widthAnchor),
                topLeftEighthLabel.widthAnchor.constraint(equalTo: topCenterLeftEighthLabel.widthAnchor),
                topCenterLeftEighthLabel.widthAnchor.constraint(equalTo: topCenterRightEighthLabel.widthAnchor),
                topCenterRightEighthLabel.widthAnchor.constraint(equalTo: topRightEighthLabel.widthAnchor),
                topRightEighthLabel.widthAnchor.constraint(equalTo: bottomLeftEighthLabel.widthAnchor),
                bottomLeftEighthLabel.widthAnchor.constraint(equalTo: bottomCenterLeftEighthLabel.widthAnchor),
                bottomCenterLeftEighthLabel.widthAnchor.constraint(equalTo: bottomCenterRightEighthLabel.widthAnchor),
                bottomCenterRightEighthLabel.widthAnchor.constraint(equalTo: bottomRightEighthLabel.widthAnchor),
                bottomRightEighthLabel.widthAnchor.constraint(equalTo: topLeftTwelfthLabel.widthAnchor),
                topLeftTwelfthLabel.widthAnchor.constraint(equalTo: topCenterLeftTwelfthLabel.widthAnchor),
                topCenterLeftTwelfthLabel.widthAnchor.constraint(equalTo: topCenterRightTwelfthLabel.widthAnchor),
                topCenterRightTwelfthLabel.widthAnchor.constraint(equalTo: topRightTwelfthLabel.widthAnchor),
                topRightTwelfthLabel.widthAnchor.constraint(equalTo: middleLeftTwelfthLabel.widthAnchor),
                middleLeftTwelfthLabel.widthAnchor.constraint(equalTo: middleCenterLeftTwelfthLabel.widthAnchor),
                middleCenterLeftTwelfthLabel.widthAnchor.constraint(equalTo: middleCenterRightTwelfthLabel.widthAnchor),
                middleCenterRightTwelfthLabel.widthAnchor.constraint(equalTo: middleRightTwelfthLabel.widthAnchor),
                middleRightTwelfthLabel.widthAnchor.constraint(equalTo: bottomLeftTwelfthLabel.widthAnchor),
                bottomLeftTwelfthLabel.widthAnchor.constraint(equalTo: bottomCenterLeftTwelfthLabel.widthAnchor),
                bottomCenterLeftTwelfthLabel.widthAnchor.constraint(equalTo: bottomCenterRightTwelfthLabel.widthAnchor),
                bottomCenterRightTwelfthLabel.widthAnchor.constraint(equalTo: bottomRightTwelfthLabel.widthAnchor),
                bottomRightTwelfthLabel.widthAnchor.constraint(equalTo: topLeftSixteenthLabel.widthAnchor),
                topLeftSixteenthLabel.widthAnchor.constraint(equalTo: topCenterLeftSixteenthLabel.widthAnchor),
                topCenterLeftSixteenthLabel.widthAnchor.constraint(equalTo: topCenterRightSixteenthLabel.widthAnchor),
                topCenterRightSixteenthLabel.widthAnchor.constraint(equalTo: topRightSixteenthLabel.widthAnchor),
                topRightSixteenthLabel.widthAnchor.constraint(equalTo: upperMiddleLeftSixteenthLabel.widthAnchor),
                upperMiddleLeftSixteenthLabel.widthAnchor.constraint(equalTo: upperMiddleCenterLeftSixteenthLabel.widthAnchor),
                upperMiddleCenterLeftSixteenthLabel.widthAnchor.constraint(equalTo: upperMiddleCenterRightSixteenthLabel.widthAnchor),
                upperMiddleCenterRightSixteenthLabel.widthAnchor.constraint(equalTo: upperMiddleRightSixteenthLabel.widthAnchor),
                upperMiddleRightSixteenthLabel.widthAnchor.constraint(equalTo: lowerMiddleLeftSixteenthLabel.widthAnchor),
                lowerMiddleLeftSixteenthLabel.widthAnchor.constraint(equalTo: lowerMiddleCenterLeftSixteenthLabel.widthAnchor),
                lowerMiddleCenterLeftSixteenthLabel.widthAnchor.constraint(equalTo: lowerMiddleCenterRightSixteenthLabel.widthAnchor),
                lowerMiddleCenterRightSixteenthLabel.widthAnchor.constraint(equalTo: lowerMiddleRightSixteenthLabel.widthAnchor),
                lowerMiddleRightSixteenthLabel.widthAnchor.constraint(equalTo: bottomLeftSixteenthLabel.widthAnchor),
                bottomLeftSixteenthLabel.widthAnchor.constraint(equalTo: bottomCenterLeftSixteenthLabel.widthAnchor),
                bottomCenterLeftSixteenthLabel.widthAnchor.constraint(equalTo: bottomCenterRightSixteenthLabel.widthAnchor),
                bottomCenterRightSixteenthLabel.widthAnchor.constraint(equalTo: bottomRightSixteenthLabel.widthAnchor),
                bottomRightSixteenthLabel.widthAnchor.constraint(equalTo: eighthsCyclingLabel.widthAnchor),
                eighthsCyclingLabel.widthAnchor.constraint(equalTo: twelfthsCyclingLabel.widthAnchor),
                twelfthsCyclingLabel.widthAnchor.constraint(equalTo: sixteenthsCyclingLabel.widthAnchor),
                sixteenthsCyclingLabel.widthAnchor.constraint(equalTo: hSplitLabel.widthAnchor),
                hSplitLabel.widthAnchor.constraint(equalTo: vSplitLabel.widthAnchor),
                largerWidthLabelStack.widthAnchor.constraint(equalTo: smallerWidthLabelStack.widthAnchor),
                largerWidthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                smallerWidthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                widthStepField.widthAnchor.constraint(equalToConstant: 160),
                topVerticalThirdShortcutView.widthAnchor.constraint(equalToConstant: 160),
                middleVerticalThirdShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomVerticalThirdShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topVerticalTwoThirdsShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomVerticalTwoThirdsShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topLeftEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topCenterLeftEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topCenterRightEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topRightEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomLeftEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomCenterLeftEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomCenterRightEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomRightEighthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topLeftTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topCenterLeftTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topCenterRightTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topRightTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                middleLeftTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                middleCenterLeftTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                middleCenterRightTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                middleRightTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomLeftTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomCenterLeftTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomCenterRightTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomRightTwelfthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topCenterLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topCenterRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                topRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                upperMiddleLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                upperMiddleCenterLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                upperMiddleCenterRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                upperMiddleRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                lowerMiddleLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                lowerMiddleCenterLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                lowerMiddleCenterRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                lowerMiddleRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomCenterLeftSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomCenterRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                bottomRightSixteenthShortcutView.widthAnchor.constraint(equalToConstant: 160),
                eighthsCyclingShortcutView.widthAnchor.constraint(equalToConstant: 160),
                twelfthsCyclingShortcutView.widthAnchor.constraint(equalToConstant: 160),
                sixteenthsCyclingShortcutView.widthAnchor.constraint(equalToConstant: 160),
                widthStepField.trailingAnchor.constraint(equalTo: largerWidthShortcutView.trailingAnchor),
                hSplitField.widthAnchor.constraint(equalToConstant: 160),
                vSplitField.widthAnchor.constraint(equalToConstant: 160),
                showEighthsCheckbox.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                cyclingCheckbox.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                smallerWidthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topVerticalThirdShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                middleVerticalThirdShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomVerticalThirdShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topVerticalTwoThirdsShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomVerticalTwoThirdsShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topLeftEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topCenterLeftEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topCenterRightEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topRightEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomLeftEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomCenterLeftEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomCenterRightEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomRightEighthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topLeftTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topCenterLeftTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topCenterRightTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topRightTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                middleLeftTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                middleCenterLeftTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                middleCenterRightTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                middleRightTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomLeftTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomCenterLeftTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomCenterRightTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomRightTwelfthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topCenterLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topCenterRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                topRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                upperMiddleLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                upperMiddleCenterLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                upperMiddleCenterRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                upperMiddleRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                lowerMiddleLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                lowerMiddleCenterLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                lowerMiddleCenterRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                lowerMiddleRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomCenterLeftSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomCenterRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                bottomRightSixteenthShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                eighthsCyclingShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                twelfthsCyclingShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                sixteenthsCyclingShortcutView.leadingAnchor.constraint(equalTo: largerWidthShortcutView.leadingAnchor),
                gridHeaderLabel.widthAnchor.constraint(equalTo: mainStackView.widthAnchor),
                cyclingHintLabel.widthAnchor.constraint(equalTo: mainStackView.widthAnchor, constant: -20),
                hSplitField.trailingAnchor.constraint(equalTo: largerWidthShortcutView.trailingAnchor),
                vSplitField.trailingAnchor.constraint(equalTo: largerWidthShortcutView.trailingAnchor)
            ])

            let containerView = NSView()
            containerView.addSubview(mainStackView)

            NSLayoutConstraint.activate([
                mainStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
                mainStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
                mainStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
                mainStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -15)
            ])

            viewController.view = containerView
            popover.contentViewController = viewController
            extraSettingsPopover = popover
        }
        extraSettingsPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    
    override func awakeFromNib() {
        initializeToggles()

        checkForUpdatesAutomaticallyCheckbox.bind(.value, to: AppDelegate.instance.updaterController.updater, withKeyPath: "automaticallyChecksForUpdates", options: nil)
        
        let appVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        
        versionLabel.stringValue = "v" + appVersionString + " (" + buildString + ")"

        updateCheckForUpdatesTitle()
        
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
        
        allowAnyShortcutCheckbox.state = Defaults.allowAnyShortcut.enabled ? .on : .off
                
        gapSlider.intValue = Int32(Defaults.gapSize.value)
        gapLabel.stringValue = "\(gapSlider.intValue) px"
        gapSlider.isContinuous = true
        
        cursorAcrossCheckbox.state = Defaults.moveCursorAcrossDisplays.userEnabled ? .on : .off

        useCursorScreenDetectionCheckbox.isHidden = !Defaults.useCursorScreenDetection.enabled
        useCursorScreenDetectionCheckbox.state = Defaults.useCursorScreenDetection.enabled ? .on : .off

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
        
        setVisibility(shown: showOptionsView, ofView: cycleSizesView, withConstraint: cycleSizesViewHeightConstraint, animated: animated)
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

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let sender = obj.object as? AutoSaveFloatField,
              let defaults: FloatDefault = sender.defaults else { return }

        if sender.stringValue.isEmpty {
            let fallback = sender.fallbackValue
            sender.stringValue = "\(Int(fallback))"
            defaults.value = fallback
            sender.defaultsSetAction?()
        }
    }
}

class AutoSaveFloatField: NSTextField {
    var defaults: FloatDefault?
    var defaultsSetAction: (() -> Void)?
    var fallbackValue: Float = 30
}
