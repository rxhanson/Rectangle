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
    @IBOutlet weak var todoCheckbox: NSButton!
    @IBOutlet weak var todoAppWidthField: AutoSaveFloatField!
    @IBOutlet weak var todoAppSidePopUpButton: NSPopUpButton!
    @IBOutlet weak var toggleTodoShortcutView: MASShortcutView!
    @IBOutlet weak var reflowTodoShortcutView: MASShortcutView!
    @IBOutlet weak var stageView: NSStackView!
    @IBOutlet weak var stageSlider: NSSlider!
    @IBOutlet weak var stageLabel: NSTextField!
    
    private var aboutTodoWindowController: NSWindowController?
    
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
    
    @IBAction func toggleTodoMode(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.todo.enabled = newSetting
        Notification.Name.todoMenuToggled.post()
    }
    
    @IBAction func showTodoModeHelp(_ sender: Any) {
        if aboutTodoWindowController == nil {
            aboutTodoWindowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "AboutTodoWindowController") as? NSWindowController
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutTodoWindowController?.showWindow(self)
    }
    
    @IBAction func setTodoAppSide(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        guard let side = TodoSidebarSide(rawValue: tag) else {
            Logger.log("Expected a pop up button to have a selected item with a valid tag matching a value of TodoSidebarSide. Got: \(String(describing: tag))")
            return
        }

        Defaults.todoSidebarSide.value = side
        
        guard Defaults.todo.userEnabled && Defaults.todoMode.enabled else { return }
        TodoManager.moveAll(false)
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
        let currentDefaults = Defaults.alternateDefaultShortcuts.enabled ? "Rectangle" : "Spectacle"
        let defaultShortcutsTitle = NSLocalizedString("Default Shortcuts", tableName: "Main", value: "", comment: "")
        let currentlyUsingText = NSLocalizedString("Currently using: ", tableName: "Main", value: "", comment: "")
        let cancelText = NSLocalizedString("Cancel", tableName: "Main", value: "", comment: "")
        let response = AlertUtil.threeButtonAlert(question: defaultShortcutsTitle, text: currentlyUsingText + currentDefaults, buttonOneText: "Rectangle", buttonTwoText: "Spectacle", buttonThreeText: cancelText)
        if response == .alertThirdButtonReturn { return }

        WindowAction.active.forEach { UserDefaults.standard.removeObject(forKey: $0.name) }
        let rectangleDefaults = response == .alertFirstButtonReturn
        if rectangleDefaults != Defaults.alternateDefaultShortcuts.enabled {
            Defaults.alternateDefaultShortcuts.enabled = rectangleDefaults
            Notification.Name.changeDefaults.post()
        }
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
        
        Notification.Name.configImported.onPost(using: {_ in
            self.initializeTodoModeSettings()
            self.initializeToggles()
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
            guard Defaults.todo.userEnabled && Defaults.todoMode.enabled else { return }
            TodoManager.moveAll(false)
        }
        todoAppSidePopUpButton.selectItem(withTag: Defaults.todoSidebarSide.value.rawValue)
        toggleTodoShortcutView.setAssociatedUserDefaultsKey(TodoManager.toggleDefaultsKey, withTransformerName: MASDictionaryTransformerName)
        reflowTodoShortcutView.setAssociatedUserDefaultsKey(TodoManager.reflowDefaultsKey, withTransformerName: MASDictionaryTransformerName)
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

        if StageUtil.stageCapable {
            stageSlider.intValue = Int32(Defaults.stageSize.value)
            stageSlider.isContinuous = true
            stageLabel.stringValue = "\(stageSlider.intValue) px"
        } else {
            stageView.isHidden = true
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
