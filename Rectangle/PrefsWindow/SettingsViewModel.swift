import SwiftUI
import AppKit

final class SettingsViewModel: ObservableObject {
    // MARK: - General Settings
    @Published var launchOnLogin: Bool {
        didSet {
            LaunchOnLogin.isEnabled = launchOnLogin
            Defaults.launchOnLogin.enabled = launchOnLogin
        }
    }

    @Published var hideMenuBarIcon: Bool {
        didSet {
            Defaults.hideMenuBarIcon.enabled = hideMenuBarIcon
            RectangleStatusItem.instance.refreshVisibility()
        }
    }

    @Published var checkForUpdatesAutomatically: Bool {
        didSet {
            AppDelegate.instance.updaterController?.updater.automaticallyChecksForUpdates = checkForUpdatesAutomatically
        }
    }

    @Published var hasPendingUpdate: Bool = false
    @Published var versionString: String = ""

    // MARK: - Window Behavior & Cycle Settings
    @Published var subsequentExecutionMode: SubsequentExecutionMode {
        didSet {
            Defaults.subsequentExecutionMode.value = subsequentExecutionMode
        }
    }

    @Published var selectedCycleSizes: Set<CycleSize> = []
    @Published var cornerCycleExpansionAxis: CornerCycleExpansionAxis {
        didSet {
            Defaults.cornerCycleExpansionAxis.value = cornerCycleExpansionAxis
        }
    }

    @Published var cooperativeCornerResize: Bool {
        didSet {
            Defaults.cooperativeCornerResize.enabled = cooperativeCornerResize
        }
    }

    @Published var gapSize: Double
    @Published var skipGapTopEdge: Bool {
        didSet {
            Defaults.skipGapTopEdge.enabled = skipGapTopEdge
        }
    }

    @Published var allowAnyShortcut: Bool {
        didSet {
            Defaults.allowAnyShortcut.enabled = allowAnyShortcut
            Notification.Name.allowAnyShortcut.post(object: allowAnyShortcut)
        }
    }

    @Published var moveCursorAcrossDisplays: Bool {
        didSet {
            Defaults.moveCursorAcrossDisplays.enabled = moveCursorAcrossDisplays
        }
    }

    @Published var useCursorScreenDetection: Bool {
        didSet {
            Defaults.useCursorScreenDetection.enabled = useCursorScreenDetection
        }
    }

    @Published var doubleClickTitleBar: Bool {
        didSet {
            handleDoubleClickTitleBarToggle(doubleClickTitleBar)
        }
    }

    @Published var autoMaximize: Bool {
        didSet {
            Defaults.autoMaximize.enabled = autoMaximize
        }
    }

    @Published var greenButtonOverride: Bool {
        didSet {
            Defaults.greenButtonOverride.enabled = greenButtonOverride
            Notification.Name.greenButtonOverride.post()
        }
    }

    @Published var combinedDisplayMode: Bool {
        didSet {
            Defaults.combinedDisplayMode.enabled = combinedDisplayMode
        }
    }

    // MARK: - Todo Mode Settings
    @Published var todoEnabled: Bool {
        didSet {
            Defaults.todo.enabled = todoEnabled
            Notification.Name.todoMenuToggled.post()
        }
    }

    @Published var todoSidebarWidth: Float {
        didSet {
            Defaults.todoSidebarWidth.value = todoSidebarWidth
        }
    }

    @Published var todoSidebarWidthUnit: TodoSidebarWidthUnit {
        didSet {
            Defaults.todoSidebarWidthUnit.value = todoSidebarWidthUnit
            TodoManager.refreshTodoScreen()
            TodoManager.changeSidebarWidthUnit(to: todoSidebarWidthUnit)
            TodoManager.moveAllIfNeeded(false)
        }
    }

    @Published var todoSidebarSide: TodoSidebarSide {
        didSet {
            Defaults.todoSidebarSide.value = todoSidebarSide
            TodoManager.moveAllIfNeeded(false)
        }
    }

    // MARK: - Stage Manager Settings
    @Published var stageSize: Double

    // MARK: - UI Conditional Flags
    var showCooperativeCornerResize: Bool { Defaults.cooperativeCornerResize.enabled }
    var showCursorScreenDetection: Bool { Defaults.useCursorScreenDetection.enabled }
    var showCombinedDisplayMode: Bool { !NSScreen.screensHaveSeparateSpaces }
    var stageCapable: Bool { StageUtil.stageCapable }

    private var aboutTodoWindowController: NSWindowController?

    // MARK: - Initialization
    init() {
        self.launchOnLogin = Defaults.launchOnLogin.enabled
        self.hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
        self.checkForUpdatesAutomatically = AppDelegate.instance.updaterController?.updater.automaticallyChecksForUpdates ?? false
        self.hasPendingUpdate = AppDelegate.instance.hasPendingUpdate

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        self.versionString = "v\(appVersion) (\(build))"

        self.subsequentExecutionMode = Defaults.subsequentExecutionMode.value
        let isCycleChanged = Defaults.cycleSizesIsChanged.enabled
        self.selectedCycleSizes = isCycleChanged ? Defaults.selectedCycleSizes.value : CycleSize.defaultSizes
        self.cornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        self.cooperativeCornerResize = Defaults.cooperativeCornerResize.enabled

        self.gapSize = Double(Defaults.gapSize.value)
        self.skipGapTopEdge = Defaults.skipGapTopEdge.enabled

        self.allowAnyShortcut = Defaults.allowAnyShortcut.enabled
        self.moveCursorAcrossDisplays = Defaults.moveCursorAcrossDisplays.userEnabled
        self.useCursorScreenDetection = Defaults.useCursorScreenDetection.enabled

        self.doubleClickTitleBar = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil
        self.autoMaximize = !Defaults.autoMaximize.userDisabled
        self.greenButtonOverride = Defaults.greenButtonOverride.enabled
        self.combinedDisplayMode = Defaults.combinedDisplayMode.userEnabled

        self.todoEnabled = Defaults.todo.userEnabled
        self.todoSidebarWidth = Defaults.todoSidebarWidth.value
        self.todoSidebarWidthUnit = Defaults.todoSidebarWidthUnit.value
        self.todoSidebarSide = Defaults.todoSidebarSide.value

        self.stageSize = Double(Defaults.stageSize.value)

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
        self.subsequentExecutionMode = Defaults.subsequentExecutionMode.value
        self.selectedCycleSizes = Defaults.cycleSizesIsChanged.enabled ? Defaults.selectedCycleSizes.value : CycleSize.defaultSizes
        self.cornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        self.gapSize = Double(Defaults.gapSize.value)
        self.skipGapTopEdge = Defaults.skipGapTopEdge.enabled
        self.allowAnyShortcut = Defaults.allowAnyShortcut.enabled
        self.moveCursorAcrossDisplays = Defaults.moveCursorAcrossDisplays.userEnabled
        self.doubleClickTitleBar = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil
        self.autoMaximize = !Defaults.autoMaximize.userDisabled
        self.greenButtonOverride = Defaults.greenButtonOverride.enabled
        self.combinedDisplayMode = Defaults.combinedDisplayMode.userEnabled
        self.todoEnabled = Defaults.todo.userEnabled
        self.todoSidebarWidth = Defaults.todoSidebarWidth.value
        self.todoSidebarWidthUnit = Defaults.todoSidebarWidthUnit.value
        self.todoSidebarSide = Defaults.todoSidebarSide.value
        self.stageSize = Double(Defaults.stageSize.value)
    }

    // MARK: - Cycle Sizes Binding Helper
    func binding(for size: CycleSize) -> Binding<Bool> {
        Binding(
            get: { self.selectedCycleSizes.contains(size) },
            set: { isChecked in
                if !Defaults.cycleSizesIsChanged.enabled {
                    Defaults.selectedCycleSizes.value = CycleSize.defaultSizes
                }
                Defaults.cycleSizesIsChanged.enabled = true

                if isChecked {
                    self.selectedCycleSizes.insert(size)
                } else {
                    self.selectedCycleSizes.remove(size)
                }
                Defaults.selectedCycleSizes.value = self.selectedCycleSizes
            }
        )
    }

    // MARK: - Action Handlers
    func commitGapSize() {
        if Float(gapSize) != Defaults.gapSize.value {
            Defaults.gapSize.value = Float(gapSize)
        }
    }

    func commitStageSize() {
        let value: Float = stageSize == 0 ? -1 : Float(stageSize)
        if value != Defaults.stageSize.value {
            Defaults.stageSize.value = value
        }
    }

    func commitTodoWidth() {
        TodoManager.moveAllIfNeeded(false)
    }

    func checkForUpdates() {
        AppDelegate.instance.updaterController?.checkForUpdates(nil)
    }

    private func handleDoubleClickTitleBarToggle(_ enabled: Bool) {
        if enabled && !TitleBarManager.systemSettingDisabled {
            let openSettings = NSLocalizedString("Open System Settings", tableName: "Main", value: "", comment: "")
            let conflictTitleText = NSLocalizedString("Conflict with system setting", tableName: "Main", value: "", comment: "")
            let conflictDescriptionText = NSLocalizedString("To let Rectangle manage the title bar double click functionality, you need to disable the corresponding macOS setting.", tableName: "Main", value: "", comment: "")
            let closeText = NSLocalizedString("DVo-aG-piG.title", tableName: "Main", value: "Close", comment: "")

            let response = AlertUtil.twoButtonAlert(question: conflictTitleText, text: conflictDescriptionText, confirmText: openSettings, cancelText: closeText)
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.dock")!)
            }
        }
        Defaults.doubleClickTitleBar.value = (enabled ? WindowAction.maximize.rawValue : -1) + 1
        Notification.Name.windowTitleBar.post()
    }

    func showTodoModeHelp() {
        if aboutTodoWindowController == nil {
            aboutTodoWindowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "AboutTodoWindowController") as? NSWindowController
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutTodoWindowController?.showWindow(nil)
    }

    func restoreDefaults() {
        let currentDefaults = Defaults.alternateDefaultShortcuts.enabled ? "Rectangle" : "Spectacle"
        let defaultShortcutsTitle = NSLocalizedString("Default Shortcuts", tableName: "Main", value: "", comment: "")
        let currentlyUsingText = NSLocalizedString("Currently using: ", tableName: "Main", value: "", comment: "")
        let cancelText = NSLocalizedString("Cancel", tableName: "Main", value: "", comment: "")

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

    func showExtrasPopover() {
        // Trigger your existing extras popover or sheet presentation logic here
    }
}
