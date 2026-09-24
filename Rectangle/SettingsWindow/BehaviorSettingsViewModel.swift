/// BehaviorSettingsViewModel.swift

import SwiftUI
import AppKit

final class BehaviorSettingsViewModel: ObservableObject {
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

    @Published var experimentalAnimations: Bool {
        didSet {
            guard oldValue != experimentalAnimations else { return }
            Defaults.experimentalWindowAnimations.enabled = experimentalAnimations
            Notification.Name.windowAnimationPreferencesChanged.post()
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
            todoSidebarWidth = Defaults.todoSidebarWidth.value
            TodoManager.moveAllIfNeeded(false)
        }
    }

    @Published var todoSidebarSide: TodoSidebarSide {
        didSet {
            Defaults.todoSidebarSide.value = todoSidebarSide
            TodoManager.moveAllIfNeeded(false)
        }
    }

    @Published var showAdditionalSizesInMenu: Bool {
        didSet {
            Defaults.showAdditionalSizesInMenu.enabled = showAdditionalSizesInMenu
            Notification.Name.showAdditionalSizesInMenuChanged.post()
        }
    }
    @Published var cyclingOverlapOffset: Bool {
        didSet { Defaults.cyclingOverlapOffset.enabled = cyclingOverlapOffset }
    }
    @Published var stackBadge: Bool {
        didSet { Defaults.stackBadge.enabled = stackBadge }
    }
    @Published var horizontalSplitRatio: Float {
        didSet {
            Defaults.horizontalSplitRatio.value = horizontalSplitRatio
            ActiveSideSplitRatios.shared.resetAll()
        }
    }
    @Published var verticalSplitRatio: Float {
        didSet {
            Defaults.verticalSplitRatio.value = verticalSplitRatio
            ActiveSideSplitRatios.shared.resetAll()
        }
    }
    @Published var halvesPreserveOtherAxisSize: Bool {
        didSet { Defaults.halvesPreserveOtherAxisSize.enabled = halvesPreserveOtherAxisSize }
    }

    // Preset Selection States
    @Published var selectedHSplitPreset: CycleSize?
    @Published var selectedVSplitPreset: CycleSize?

    
    @Published var repeatedMaximizeRestoresPrevious: Bool {
        didSet { Defaults.repeatedMaximizeRestoresPrevious.enabled = repeatedMaximizeRestoresPrevious }
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

        self.subsequentExecutionMode = Defaults.subsequentExecutionMode.value
        let isCycleChanged = Defaults.cycleSizesIsChanged.enabled
        self.selectedCycleSizes = isCycleChanged ? Defaults.selectedCycleSizes.value : CycleSize.defaultSizes
        self.cornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        self.cooperativeCornerResize = Defaults.cooperativeCornerResize.enabled

        self.gapSize = Double(Defaults.gapSize.value)
        self.skipGapTopEdge = Defaults.skipGapTopEdge.enabled

        self.moveCursorAcrossDisplays = Defaults.moveCursorAcrossDisplays.userEnabled
        self.useCursorScreenDetection = Defaults.useCursorScreenDetection.enabled

        self.doubleClickTitleBar = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil
        self.autoMaximize = !Defaults.autoMaximize.userDisabled
        self.greenButtonOverride = Defaults.greenButtonOverride.enabled
        self.experimentalAnimations = Defaults.experimentalWindowAnimations.enabled
        self.combinedDisplayMode = Defaults.combinedDisplayMode.userEnabled
        self.repeatedMaximizeRestoresPrevious = Defaults.repeatedMaximizeRestoresPrevious.enabled

        self.todoEnabled = Defaults.todo.userEnabled
        self.todoSidebarWidth = Defaults.todoSidebarWidth.value
        self.todoSidebarWidthUnit = Defaults.todoSidebarWidthUnit.value
        self.todoSidebarSide = Defaults.todoSidebarSide.value

        self.stageSize = Double(Defaults.stageSize.value)
        
        let hRatio = Defaults.horizontalSplitRatio.value
        let vRatio = Defaults.verticalSplitRatio.value

        self.showAdditionalSizesInMenu = Defaults.showAdditionalSizesInMenu.userEnabled
        self.cyclingOverlapOffset = Defaults.cyclingOverlapOffset.userEnabled
        self.stackBadge = Defaults.stackBadge.userEnabled
        self.horizontalSplitRatio = hRatio
        self.verticalSplitRatio = vRatio
        self.halvesPreserveOtherAxisSize = Defaults.halvesPreserveOtherAxisSize.enabled

        self.selectedHSplitPreset = CycleSize.matching(percentValue: hRatio)
        self.selectedVSplitPreset = CycleSize.matching(percentValue: vRatio)

        setupObservers()
    }

    private func setupObservers() {
        Notification.Name.configImported.onPost { [weak self] _ in
            self?.reloadFromDefaults()
        }
        Notification.Name.stackBadgeChanged.onPost { [weak self] _ in
            self?.stackBadge = Defaults.stackBadge.userEnabled
        }
    }

    func reloadFromDefaults() {
        self.subsequentExecutionMode = Defaults.subsequentExecutionMode.value
        self.selectedCycleSizes = Defaults.cycleSizesIsChanged.enabled ? Defaults.selectedCycleSizes.value : CycleSize.defaultSizes
        self.cornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        self.gapSize = Double(Defaults.gapSize.value)
        self.skipGapTopEdge = Defaults.skipGapTopEdge.enabled
        self.moveCursorAcrossDisplays = Defaults.moveCursorAcrossDisplays.userEnabled
        self.doubleClickTitleBar = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil
        self.autoMaximize = !Defaults.autoMaximize.userDisabled
        self.greenButtonOverride = Defaults.greenButtonOverride.enabled
        self.experimentalAnimations = Defaults.experimentalWindowAnimations.enabled
        self.combinedDisplayMode = Defaults.combinedDisplayMode.userEnabled
        self.todoEnabled = Defaults.todo.userEnabled
        self.todoSidebarWidth = Defaults.todoSidebarWidth.value
        self.todoSidebarWidthUnit = Defaults.todoSidebarWidthUnit.value
        self.todoSidebarSide = Defaults.todoSidebarSide.value
        self.stackBadge = Defaults.stackBadge.userEnabled
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
            let openSettings = String(localized: "Open System Settings")
            let conflictTitleText = String(localized: "Conflict with system setting")
            let conflictDescriptionText = String(localized: "To let Rectangle manage the title bar double click functionality, you need to disable the corresponding macOS setting.")
            let closeText = String(localized: "Close")

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

    func selectHSplitPreset(_ preset: CycleSize?) {
        selectedHSplitPreset = preset
        if let percentValue = preset?.percentValue {
            horizontalSplitRatio = percentValue
        }
    }

    func selectVSplitPreset(_ preset: CycleSize?) {
        selectedVSplitPreset = preset
        if let percentValue = preset?.percentValue {
            verticalSplitRatio = percentValue
        }
    }
}
