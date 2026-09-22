/// ExtraSettings.swift

import SwiftUI

final class TileSettingsViewModel: ObservableObject {
    @Published var tileColumnsMaxWindows: Int {
        didSet { Defaults.tileColumnsMaxWindows.value = tileColumnsMaxWindows }
    }
    @Published var tileRowsMaxWindows: Int {
        didSet { Defaults.tileRowsMaxWindows.value = tileRowsMaxWindows }
    }

    init() {
        self.tileColumnsMaxWindows = Defaults.tileColumnsMaxWindows.value
        self.tileRowsMaxWindows = Defaults.tileRowsMaxWindows.value
    }
}

final class WindowSizingSettingsViewModel: ObservableObject {
    @Published var widthStepSize: Int {
        didSet { Defaults.widthStepSize.value = Float(widthStepSize) }
    }

    init() {
        self.widthStepSize = Int(Defaults.widthStepSize.value)
    }
}

// MARK: - Shared Helpers

private var integerFormatter: NumberFormatter {
    let formatter = NumberFormatter()
    formatter.allowsFloats = false
    formatter.minimum = 1
    return formatter
}

// MARK: - Standalone Popover Views

struct TileSettingsView: View {
    @StateObject private var viewModel = TileSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Tile Windows in Rows/Columns", tableName: "Main", value: "", comment: ""))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(NSLocalizedString("Maximum windows per column", tableName: "Main", value: "", comment: ""))
                    Stepper(value: $viewModel.tileColumnsMaxWindows, in: 1...Int.max) {
                        TextField("", value: $viewModel.tileColumnsMaxWindows, formatter: integerFormatter)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                    }
                }
                GridRow {
                    Text(NSLocalizedString("Maximum windows per row", tableName: "Main", value: "", comment: ""))
                    Stepper(value: $viewModel.tileRowsMaxWindows, in: 1...Int.max) {
                        TextField("", value: $viewModel.tileRowsMaxWindows, formatter: integerFormatter)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding()
    }
}

struct WindowSizingSettingsView: View {
    @StateObject private var viewModel = WindowSizingSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Window Sizing", tableName: "Main", value: "", comment: ""))
                .font(.headline)

            HStack {
                Text(NSLocalizedString("Width Step (px)", tableName: "Main", value: "", comment: ""))
                Spacer()
                TextField("", value: $viewModel.widthStepSize, formatter: integerFormatter)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding()
    }
}
