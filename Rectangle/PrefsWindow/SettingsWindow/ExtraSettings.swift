/// ExtraSettings.swift

import SwiftUI
import Combine
import MASShortcut // Required for MASShortcutViewRepresentable

// MARK: - View Model

final class ExtraSettingsViewModel: ObservableObject {
    
    @Published var tileColumnsMaxWindows: Int {
        didSet { Defaults.tileColumnsMaxWindows.value = tileColumnsMaxWindows }
    }
    @Published var tileRowsMaxWindows: Int {
        didSet { Defaults.tileRowsMaxWindows.value = tileRowsMaxWindows }
    }

    @Published var widthStepSize: Int {
        didSet { Defaults.widthStepSize.value = Float(widthStepSize) }
    }

    init() {
        self.tileColumnsMaxWindows = Defaults.tileColumnsMaxWindows.value
        self.tileRowsMaxWindows = Defaults.tileRowsMaxWindows.value
        self.widthStepSize = Int(Defaults.widthStepSize.value)
    }

}

// MARK: - SwiftUI View

import SwiftUI

struct ExtraSettingsSections: View {
    @StateObject private var viewModel = ExtraSettingsViewModel()

    var body: some View {
        Group {
            Section {
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
            } header: {
                Text(NSLocalizedString("Tile Windows in Rows/Columns", tableName: "Main", value: "", comment: ""))
            }
            
            // MARK: - Window Sizing Steps
            Section {
                HStack {
                    Text(NSLocalizedString("Width Step (px)", tableName: "Main", value: "", comment: ""))
                    Spacer()
                    TextField("", value: $viewModel.widthStepSize, formatter: integerFormatter)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(NSLocalizedString("Window Sizing", tableName: "Main", value: "", comment: ""))
            }

        }
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        return formatter
    }
}
