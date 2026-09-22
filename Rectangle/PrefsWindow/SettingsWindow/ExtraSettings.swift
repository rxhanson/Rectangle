/// ExtraSettings.swift

import SwiftUI
import Combine
import MASShortcut // Required for MASShortcutViewRepresentable

// MARK: - View Model

final class ExtraSettingsViewModel: ObservableObject {
    
    // MARK: Published Properties (State)
    @Published var tileColumnsMaxWindows: Int {
        didSet { Defaults.tileColumnsMaxWindows.value = tileColumnsMaxWindows }
    }
    @Published var tileRowsMaxWindows: Int {
        didSet { Defaults.tileRowsMaxWindows.value = tileRowsMaxWindows }
    }
    @Published var widthStepSize: Int {
        didSet { Defaults.widthStepSize.value = Float(widthStepSize) }
    }
    @Published var showAdditionalSizesInMenu: Bool {
        didSet { Defaults.showAdditionalSizesInMenu.enabled = showAdditionalSizesInMenu }
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
            // Reset active ratios when user changes presets or manual ratio
            // ActiveSideSplitRatios.shared.resetAll()
        }
    }
    @Published var verticalSplitRatio: Float {
        didSet {
            Defaults.verticalSplitRatio.value = verticalSplitRatio
            // ActiveSideSplitRatios.shared.resetAll()
        }
    }
    @Published var halvesPreserveOtherAxisSize: Bool {
        didSet { Defaults.halvesPreserveOtherAxisSize.enabled = halvesPreserveOtherAxisSize }
    }
    @Published var repeatedMaximizeRestoresPrevious: Bool {
        didSet { Defaults.repeatedMaximizeRestoresPrevious.enabled = repeatedMaximizeRestoresPrevious }
    }

    // Preset Selection States
    @Published var selectedHSplitPreset: CycleSize?
    @Published var selectedVSplitPreset: CycleSize?

    // MARK: - Initialization
    init() {
        // Read initial values from Defaults / App Storage
        let hRatio = Defaults.horizontalSplitRatio.value
        let vRatio = Defaults.verticalSplitRatio.value

        self.tileColumnsMaxWindows = Defaults.tileColumnsMaxWindows.value
        self.tileRowsMaxWindows = Defaults.tileRowsMaxWindows.value
        self.widthStepSize = Int(Defaults.widthStepSize.value)
        self.showAdditionalSizesInMenu = Defaults.showAdditionalSizesInMenu.userEnabled
        self.cyclingOverlapOffset = Defaults.cyclingOverlapOffset.userEnabled
        self.stackBadge = Defaults.stackBadge.userEnabled
        self.horizontalSplitRatio = hRatio
        self.verticalSplitRatio = vRatio
        self.halvesPreserveOtherAxisSize = Defaults.halvesPreserveOtherAxisSize.enabled
        self.repeatedMaximizeRestoresPrevious = Defaults.repeatedMaximizeRestoresPrevious.enabled

        // Match existing ratios to presets or set as custom ("Other")
        self.selectedHSplitPreset = CycleSize(rawValue: Int(hRatio))
        self.selectedVSplitPreset = CycleSize(rawValue: Int(vRatio))
    }

    // MARK: - Actions
    
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

// MARK: - SwiftUI View

struct ExtraSettingsView: View {
    @StateObject private var viewModel = ExtraSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // MARK: - Tile Windows in Rows/Columns
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Tile Windows in Rows/Columns", tableName: "Main", value: "", comment: "General settings group for multi-window grid limits"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(NSLocalizedString("Maximum windows per column", tableName: "Main", value: "", comment: "Maximum windows stacked in each tiled column"))
                        Stepper(value: $viewModel.tileColumnsMaxWindows, in: 1...Int.max) {
                            TextField("", value: $viewModel.tileColumnsMaxWindows, formatter: integerFormatter)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    GridRow {
                        Text(NSLocalizedString("Maximum windows per row", tableName: "Main", value: "", comment: "Maximum windows placed side by side in each tiled row"))
                        Stepper(value: $viewModel.tileRowsMaxWindows, in: 1...Int.max) {
                            TextField("", value: $viewModel.tileRowsMaxWindows, formatter: integerFormatter)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            Divider()

            // MARK: - Width Step Size
            HStack {
                Text(NSLocalizedString("Width Step (px)", tableName: "Main", value: "", comment: ""))
                Spacer()
                TextField("", value: $viewModel.widthStepSize, formatter: integerFormatter)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }

            Divider()

            // MARK: - Grid Positions
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Grid Positions", tableName: "Main", value: "", comment: ""))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(NSLocalizedString("Press the shortcut repeatedly to cycle through all positions in the grid.", tableName: "Main", value: "", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Toggle(NSLocalizedString("Show additional sizes in menu", tableName: "Main", value: "", comment: ""), isOn: $viewModel.showAdditionalSizesInMenu)
                Toggle(NSLocalizedString("Offset window position on overlap", tableName: "Main", value: "", comment: ""), isOn: $viewModel.cyclingOverlapOffset)
                Toggle(NSLocalizedString("Show stacked window list on hover", tableName: "Main", value: "", comment: ""), isOn: $viewModel.stackBadge)

                HStack {
                    Text(NSLocalizedString("Toggle window list", tableName: "Main", value: "", comment: ""))
                    Spacer()
                    MASShortcutViewRepresentable(defaultsKey: StackBadgeManager.toggleDefaultsKey, validator: nil)
                        .frame(width: 160, height: 19)
                }
            }

            Divider()

            // MARK: - Side Split Ratios
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Side Split Ratio", tableName: "Main", value: "", comment: ""))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Horizontal Split
                HStack {
                    Text(NSLocalizedString("Horizontal (L/R, %)", tableName: "Main", value: "", comment: ""))
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { viewModel.selectedHSplitPreset },
                        set: { viewModel.selectHSplitPreset($0) }
                    )) {
                        // TODO: Loop through CycleSize.sortedSizes if available in your project
                        Text("50 / 50").tag(Optional(CycleSize.oneHalf))
                        Text("Other").tag(Optional<CycleSize>.none)
                    }
                    .labelsHidden()
                    .frame(width: 110)

                    if viewModel.selectedHSplitPreset == nil {
                        TextField("", value: $viewModel.horizontalSplitRatio, formatter: percentFormatter)
                            .frame(width: 45)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Vertical Split
                HStack {
                    Text(NSLocalizedString("Vertical (T/B, %)", tableName: "Main", value: "", comment: ""))
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { viewModel.selectedVSplitPreset },
                        set: { viewModel.selectVSplitPreset($0) }
                    )) {
                        Text("50 / 50").tag(Optional(CycleSize.oneHalf))
                        Text("Other").tag(Optional<CycleSize>.none)
                    }
                    .labelsHidden()
                    .frame(width: 110)

                    if viewModel.selectedVSplitPreset == nil {
                        TextField("", value: $viewModel.verticalSplitRatio, formatter: percentFormatter)
                            .frame(width: 45)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Toggle(NSLocalizedString("Half actions preserve the window's size on the other axis", tableName: "Main", value: "", comment: ""), isOn: $viewModel.halvesPreserveOtherAxisSize)
                    .help(NSLocalizedString("Left Half then Top Half moves the window to the top left quarter; the action for the opposite edge expands it back.", tableName: "Main", value: "", comment: ""))

                Toggle(NSLocalizedString("Repeated Maximize restores the previous size and position", tableName: "Main", value: "", comment: ""), isOn: $viewModel.repeatedMaximizeRestoresPrevious)
                    .help(NSLocalizedString("After Rectangle maximizes or almost maximizes a window, executing the same action again moves the window back to its previous size and position.", tableName: "Main", value: "", comment: ""))
            }
        }
        .padding(15)
        .frame(width: 380)
    }

    // MARK: - Formatters
    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        return formatter
    }

    private var percentFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 99
        return formatter
    }
}
