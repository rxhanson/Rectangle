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

            NSLayoutConstraint.activate([
                headerLabel.widthAnchor.constraint(equalTo: mainStackView.widthAnchor),
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
                widthStepField.trailingAnchor.constraint(equalTo: largerWidthShortcutView.trailingAnchor)
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
            sender.stringValue = "30"
            defaults.value = 30
            sender.defaultsSetAction?()
        }
    }
}

class AutoSaveFloatField: NSTextField {
    var defaults: FloatDefault?
    var defaultsSetAction: (() -> Void)?
}
