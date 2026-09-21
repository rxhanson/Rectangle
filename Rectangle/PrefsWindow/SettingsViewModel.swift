import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    // General Section
    @Published var launchOnLogin: Bool {
        didSet {
            if oldValue != launchOnLogin {
                Defaults.launchOnLogin.enabled = launchOnLogin
                LaunchOnLogin.isEnabled = launchOnLogin
            }
        }
    }
    
    @Published var subsequentExecutionMode: SubsequentExecutionMode {
        didSet {
            if oldValue != subsequentExecutionMode {
                Defaults.subsequentExecutionMode.value = subsequentExecutionMode
                // In SettingsViewController, this calls initializeCycleSizesView(animated: true)
                NotificationCenter.default.post(name: .init("initializeCycleSizesView"), object: nil)
            }
        }
    }

    @Published var allowAnyShortcut: Bool {
        didSet {
            if oldValue != allowAnyShortcut {
                Defaults.allowAnyShortcut.enabled = allowAnyShortcut
                Notification.Name.allowAnyShortcut.post(object: allowAnyShortcut)
            }
        }
    }

    @Published var hideMenuBarIcon: Bool {
        didSet {
            if oldValue != hideMenuBarIcon {
                Defaults.hideMenuBarIcon.enabled = hideMenuBarIcon
                RectangleStatusItem.instance.refreshVisibility()
            }
        }
    }

    @Published var checkForUpdatesAutomatically: Bool {
        didSet {
            if oldValue != checkForUpdatesAutomatically {
                Defaults.SUEnableAutomaticChecks.enabled = checkForUpdatesAutomatically
            }
        }
    }

    // Gap Section
    @Published var gapSize: Float {
        didSet {
            if oldValue != gapSize {
                Defaults.gapSize.value = gapSize
            }
        }
    }

    @Published var skipGapTopEdge: Bool {
        didSet {
            if oldValue != skipGapTopEdge {
                Defaults.skipGapTopEdge.enabled = skipGapTopEdge
            }
        }
    }

    // Window & Display Section
    @Published var moveCursorAcrossDisplays: Bool {
        didSet {
            if oldValue != moveCursorAcrossDisplays {
                Defaults.moveCursorAcrossDisplays.enabled = moveCursorAcrossDisplays
            }
        }
    }

    @Published var useCursorScreenDetection: Bool {
        didSet {
            if oldValue != useCursorScreenDetection {
                Defaults.useCursorScreenDetection.enabled = useCursorScreenDetection
            }
        }
    }

    @Published var doubleClickTitleBar: WindowAction? {
        didSet {
            if oldValue != doubleClickTitleBar {
                let val = (doubleClickTitleBar == nil) ? -1 : doubleClickTitleBar!.rawValue
                Defaults.doubleClickTitleBar.value = val + 1
                Notification.Name.windowTitleBar.post()
            }
        }
    }
    
    // For handling the alert in SwiftUI
    @Published var showDoubleClickConflictAlert: Bool = false

    @Published var combinedDisplayMode: Bool {
        didSet {
            if oldValue != combinedDisplayMode {
                Defaults.combinedDisplayMode.enabled = combinedDisplayMode
            }
        }
    }

    @Published var greenButtonOverride: Bool {
        didSet {
            if oldValue != greenButtonOverride {
                Defaults.greenButtonOverride.enabled = greenButtonOverride
                Notification.Name.greenButtonOverride.post()
            }
        }
    }

    @Published var autoMaximize: Bool {
        didSet {
            if oldValue != autoMaximize {
                Defaults.autoMaximize.enabled = autoMaximize
            }
        }
    }

    @Published var halvesPreserveOtherAxisSize: Bool {
        didSet {
            if oldValue != halvesPreserveOtherAxisSize {
                Defaults.halvesPreserveOtherAxisSize.enabled = halvesPreserveOtherAxisSize
            }
        }
    }

    @Published var repeatedMaximizeRestoresPrevious: Bool {
        didSet {
            if oldValue != repeatedMaximizeRestoresPrevious {
                Defaults.repeatedMaximizeRestoresPrevious.enabled = repeatedMaximizeRestoresPrevious
            }
        }
    }

    // Stage Section
    @Published var stageSize: Float {
        didSet {
            if oldValue != stageSize {
                let value = stageSize == 0 ? -1 : stageSize
                Defaults.stageSize.value = value
            }
        }
    }

    // Cycle Sizes Section
    @Published var selectedCycleSizes: Set<CycleSize> {
        didSet {
            if oldValue != selectedCycleSizes {
                Defaults.selectedCycleSizes.value = selectedCycleSizes
                Defaults.cycleSizesIsChanged.enabled = true
            }
        }
    }

    @Published var cornerCycleExpansionAxis: CornerCycleExpansionAxis {
        didSet {
            if oldValue != cornerCycleExpansionAxis {
                Defaults.cornerCycleExpansionAxis.value = cornerCycleExpansionAxis
            }
        }
    }

    @Published var cooperativeCornerResize: Bool {
        didSet {
            if oldValue != cooperativeCornerResize {
                Defaults.cooperativeCornerResize.enabled = cooperativeCornerResize
            }
        }
    }

    // Todo Section
    @Published var todoMode: Bool {
        didSet {
            if oldValue != todoMode {
                Defaults.todo.enabled = todoMode
                Notification.Name.todoMenuToggled.post()
            }
        }
    }

    @Published var todoSidebarWidth: Float {
        didSet {
            if oldValue != todoSidebarWidth {
                Defaults.todoSidebarWidth.value = todoSidebarWidth
                TodoManager.changeSidebarWidthUnit(to: TodoSidebarWidthUnit(rawValue: Defaults.todoSidebarWidthUnit.value.rawValue) ?? .pixels)
                TodoManager.moveAllIfNeeded(false)
            }
        }
    }

    @Published var todoSidebarWidthUnit: TodoSidebarWidthUnit {
        didSet {
            if oldValue != todoSidebarWidthUnit {
                Defaults.todoSidebarWidthUnit.value = todoSidebarWidthUnit
                TodoManager.refreshTodoScreen()
                TodoManager.changeSidebarWidthUnit(to: todoSidebarWidthUnit)
                TodoManager.moveAllIfNeeded(false)
            }
        }
    }

    @Published var todoSidebarSide: TodoSidebarSide {
        didSet {
            if oldValue != todoSidebarSide {
                Defaults.todoSidebarSide.value = todoSidebarSide
                TodoManager.moveAllIfNeeded(false)
            }
        }
    }

    init() {
        self.launchOnLogin = Defaults.launchOnLogin.enabled
        self.subsequentExecutionMode = Defaults.subsequentExecutionMode.value
        self.allowAnyShortcut = Defaults.allowAnyShortcut.enabled
        self.hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
        self.checkForUpdatesAutomatically = Defaults.SUEnableAutomaticChecks.enabled
        self.gapSize = Defaults.gapSize.value
        self.skipGapTopEdge = Defaults.skipGapTopEdge.enabled
        self.moveCursorAcrossDisplays = Defaults.moveCursorAcrossDisplays.userEnabled
        self.useCursorScreenDetection = Defaults.useCursorScreenDetection.enabled
        let doubleClickVal = Defaults.doubleClickTitleBar.value - 1
        self.doubleClickTitleBar = WindowAction(rawValue: doubleClickVal)
        self.combinedDisplayMode = Defaults.combinedDisplayMode.userEnabled
        self.greenButtonOverride = Defaults.greenButtonOverride.enabled
        self.autoMaximize = !Defaults.autoMaximize.userDisabled
        self.halvesPreserveOtherAxisSize = Defaults.halvesPreserveOtherAxisSize.enabled
        self.repeatedMaximizeRestoresPrevious = Defaults.repeatedMaximizeRestoresPrevious.enabled
        if Defaults.stageSize.value < 0 { self.stageSize = 0 } else { self.stageSize = Defaults.stageSize.value }

        self.selectedCycleSizes = Defaults.selectedCycleSizes.value
        self.cornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        self.cooperativeCornerResize = Defaults.cooperativeCornerResize.enabled
        self.todoMode = Defaults.todo.userEnabled
        self.todoSidebarWidth = Defaults.todoSidebarWidth.value
        self.todoSidebarWidthUnit = Defaults.todoSidebarWidthUnit.value
        self.todoSidebarSide = Defaults.todoSidebarSide.value
    }

    func requestDoubleClickTitleBarChange(to newSetting: Bool) {
        if newSetting && !TitleBarManager.systemSettingDisabled {
            showDoubleClickConflictAlert = true
        } else {
            doubleClickTitleBar = newSetting ? .maximize : nil
        }
    }
    
    func confirmDoubleClickTitleBarChange() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.dock")!)
        doubleClickTitleBar = .maximize
        showDoubleClickConflictAlert = false
    }

    func cancelDoubleClickTitleBarChange() {
        showDoubleClickConflictAlert = false
    }
    
    func checkForUpdates() {
        AppDelegate.instance.updaterController?.checkForUpdates(nil)
    }

    func restoreDefaults() {
        // Simplification for now, real implementation would have the alert
        let rectangleDefaults = true // Defaulting to Rectangle for this step
        WindowAction.active.forEach { UserDefaults.standard.removeObject(forKey: $0.name) }
        Defaults.alternateDefaultShortcuts.enabled = rectangleDefaults
        Notification.Name.changeDefaults.post()
        
        Defaults.portraitSnapAreas.typedValue = nil
        Defaults.landscapeSnapAreas.typedValue = nil
        Notification.Name.defaultSnapAreas.post()
    }

    func exportConfig() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "RectangleConfig"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let jsonString = Defaults.encoded() {
                try? jsonString.write(to: url, atomically: false, encoding: .utf8)
            }
        }
    }

    func importConfig() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        if openPanel.runModal() == .OK, let url = openPanel.url {
            Defaults.load(fileUrl: url)
        }
    }
}
