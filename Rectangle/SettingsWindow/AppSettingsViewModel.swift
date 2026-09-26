/// AppSettingsViewModel.swift

import SwiftUI
import AppKit

@Observable
final class AppSettingsViewModel {
    // MARK: - General Settings
     var launchOnLogin: Bool {
        didSet {
            LaunchOnLogin.isEnabled = launchOnLogin
            Defaults.launchOnLogin.enabled = launchOnLogin
        }
    }

     var hideMenuBarIcon: Bool {
        didSet {
            Defaults.hideMenuBarIcon.enabled = hideMenuBarIcon
            RectangleStatusItem.instance.refreshVisibility()
        }
    }

     var checkForUpdatesAutomatically: Bool {
        didSet {
            AppDelegate.instance.updaterController?.updater.automaticallyChecksForUpdates = checkForUpdatesAutomatically
        }
    }

     var hasPendingUpdate: Bool = false
     var versionString: String = ""

     var allowAnyShortcut: Bool {
        didSet {
            Defaults.allowAnyShortcut.enabled = allowAnyShortcut
            Notification.Name.allowAnyShortcut.post(object: allowAnyShortcut)
        }
    }

    // MARK: - Initialization
    init() {
        self.launchOnLogin = Defaults.launchOnLogin.enabled
        self.hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
        self.checkForUpdatesAutomatically = AppDelegate.instance.updaterController?.updater.automaticallyChecksForUpdates ?? false
        self.hasPendingUpdate = AppDelegate.instance.hasPendingUpdate
        self.allowAnyShortcut = Defaults.allowAnyShortcut.enabled

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        self.versionString = "v\(appVersion) (\(build))"

        setupObservers()
    }

    private func setupObservers() {
        Notification.Name.menuBarIconHidden.onPost { [weak self] _ in
            self?.hideMenuBarIcon = true
        }

        Notification.Name.updateAvailability.onPost { [weak self] _ in
            self?.hasPendingUpdate = AppDelegate.instance.hasPendingUpdate
        }

        Notification.Name.configImported.onPost { [weak self] _ in
            self?.reloadFromDefaults()
        }
    }

    func reloadFromDefaults() {
        self.launchOnLogin = Defaults.launchOnLogin.enabled
        self.hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
        self.allowAnyShortcut = Defaults.allowAnyShortcut.enabled
    }

    func checkForUpdates() {
        AppDelegate.instance.updaterController?.checkForUpdates(nil)
    }

    func restoreDefaults() {
        let currentDefaults = Defaults.alternateDefaultShortcuts.enabled ? "Rectangle" : "Spectacle"
        let defaultShortcutsTitle = String(localized: "Default Shortcuts")
        let currentlyUsingText = String(localized: "Currently using: ")
        let cancelText = String(localized: "Cancel")

        let response = AlertUtil.threeButtonAlert(question: defaultShortcutsTitle, text: currentlyUsingText + currentDefaults, buttonOneText: "Rectangle", buttonTwoText: "Spectacle", buttonThreeText: cancelText)
        if response == .alertThirdButtonReturn { return }

        let rectangleDefaults = (response == .alertFirstButtonReturn)
        WindowAction.active.forEach { UserDefaults.standard.removeObject(forKey: $0.name) }
        Defaults.alternateDefaultShortcuts.enabled = rectangleDefaults
        Notification.Name.changeDefaults.post()

        Defaults.portraitSnapAreas.typedValue = nil
        Defaults.landscapeSnapAreas.typedValue = nil
        Notification.Name.defaultSnapAreas.post()
    }

    func exportConfig() {
        Notification.Name.windowSnapping.post(object: false)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "RectangleConfig"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                if let jsonString = Defaults.encoded() {
                    try jsonString.write(to: url, atomically: false, encoding: .utf8)
                }
            } catch {
                Logger.log(error.localizedDescription)
            }
        }
        Notification.Name.windowSnapping.post(object: true)
    }

    func importConfig() {
        Notification.Name.windowSnapping.post(object: false)
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            Defaults.load(fileUrl: url)
        }
        Notification.Name.windowSnapping.post(object: true)
    }
}
