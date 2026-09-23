// BehaviorSettingsView.swift

import AppKit
import SwiftUI

// MARK: - AppKit View Controller Wrapper
final class BehaviorSettingsViewController: NSViewController {
    private var hostingController: NSHostingController<BehaviorSettingsView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let swiftUIView = BehaviorSettingsView()
        let hostingController = NSHostingController(rootView: swiftUIView)
        self.hostingController = hostingController
        
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - SwiftUI Settings View
struct BehaviorSettingsView: View {
    @StateObject private var viewModel = BehaviorSettingsViewModel()
    @State private var isMaximizeExpanded = false // Controls disclosure state

    // Cached formatter to avoid expensive re-allocations during view body updates
    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 99
        return formatter
    }()

    var body: some View {
        Form {
            // MARK: - Cycle Sizes & Window Behaviors
            Section {
                HStack {
                    Text("Repeated commands")
                    Spacer()
                    Picker("", selection: $viewModel.subsequentExecutionMode) {
                        ForEach(SubsequentExecutionMode.ordered, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                
                if viewModel.subsequentExecutionMode.resizes {
                    VStack(alignment: .leading, spacing: 8) {
                        // Keep fraction choices as compact checkboxes
                        HStack(spacing: 12) {
                            Spacer()
                            ForEach(CycleSize.sortedSizes, id: \.self) { size in
                                Toggle(size.title, isOn: viewModel.binding(for: size))
                                    .toggleStyle(.checkbox)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Text("Cyclic corner shortcuts expand:")
                            Spacer()
                            Picker("", selection: $viewModel.cornerCycleExpansionAxis) {
                                Text("horizontally").tag(CornerCycleExpansionAxis.horizontal)
                                Text("vertically").tag(CornerCycleExpansionAxis.vertical)
                            }
                            .pickerStyle(.radioGroup)
                            .horizontalRadioGroupLayout()
                        }
                        
                        if viewModel.showCooperativeCornerResize {
                            Toggle("Resize adjacent windows when cycling side or corner shortcuts", isOn: $viewModel.cooperativeCornerResize)
                                .toggleStyle(.switch)
                        }
                    }
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            // MARK: - Gaps
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Gaps between windows")
                        Slider(
                            value: $viewModel.gapSize,
                            in: 0...100,
                            onEditingChanged: { editing in
                                if !editing { viewModel.commitGapSize() }
                            }
                        )
                        Text("\(Int(viewModel.gapSize)) px")
                            .frame(width: 45, alignment: .trailing)
                    }
                    
                    if viewModel.gapSize > 0 {
                        Toggle("Remove top gap when snapping to top edge", isOn: $viewModel.skipGapTopEdge)
                            .toggleStyle(.switch)
                    }
                }
            }
            
            // MARK: - Cursor & Display Rules
            Section {
                Toggle("Move cursor along with window across displays", isOn: $viewModel.moveCursorAcrossDisplays)
                Toggle(NSLocalizedString("Half actions preserve the window's size on the other axis", tableName: "Main", value: "", comment: ""), isOn: $viewModel.halvesPreserveOtherAxisSize)
                Toggle(NSLocalizedString("Show Extra shortcuts in menu", tableName: "Main", value: "", comment: ""), isOn: $viewModel.showAdditionalSizesInMenu)
            }

            // MARK: - Todo Mode
            Section {
                HStack {
                    Toggle(isOn: $viewModel.todoEnabled) {
                        HStack(spacing: 4) {
                            Text("Show Todo Mode in menu")
                            Button(action: viewModel.showTodoModeHelp) {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if viewModel.todoEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keep a chosen application visible on the right of your primary screen at all times")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Todo app width")

                            Spacer()

                            HStack(spacing: 4) {
                                TextField("", value: $viewModel.todoSidebarWidth, format: .number)
                                    .frame(width: 100)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { viewModel.commitTodoWidth() }

                                Picker("", selection: $viewModel.todoSidebarWidthUnit) {
                                    Text("px").tag(TodoSidebarWidthUnit.pixels)
                                    Text("%").tag(TodoSidebarWidthUnit.pct)
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                        
                        HStack {
                            Text("Todo side")
                            Spacer()
                            Picker("", selection: $viewModel.todoSidebarSide) {
                                Text("Left").tag(TodoSidebarSide.left)
                                Text("Right").tag(TodoSidebarSide.right)
                            }
                            .frame(width: 90)
                        }
                        
                        HStack {
                            Text("Toggle Todo")
                            Spacer()
                            MASShortcutViewRepresentable(
                                defaultsKey: TodoManager.toggleDefaultsKey,
                                validator: TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey)
                            )
                            .frame(width: 130, height: 22)
                        }

                        HStack {
                            Text("Reflow Todo")
                            Spacer()
                            MASShortcutViewRepresentable(
                                defaultsKey: TodoManager.reflowDefaultsKey,
                                validator: TodoShortcutValidator(defaultsKey: TodoManager.reflowDefaultsKey)
                            )
                            .frame(width: 130, height: 22)
                        }
                    }
                    .padding(.leading, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            // MARK: - Maximize (Disclosure Section)
            Section {
                DisclosureGroup("Maximize Settings", isExpanded: $isMaximizeExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        if viewModel.showCursorScreenDetection {
                            Toggle("Use cursor screen detection", isOn: $viewModel.useCursorScreenDetection)
                        }
                        
                        Toggle("Double-click window title bar to maximize/restore", isOn: $viewModel.doubleClickTitleBar)
                        Toggle("Preserve maximize state when moving across displays", isOn: $viewModel.autoMaximize)
                        
                        Toggle(NSLocalizedString("Repeated Maximize restores the previous size and position", tableName: "Main", value: "", comment: ""), isOn: $viewModel.repeatedMaximizeRestoresPrevious)

                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Green stoplight button maximizes instead of Full Screen", isOn: $viewModel.greenButtonOverride)
                            Text("Hold any modifier key or use the window menu for default macOS behavior")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.showCombinedDisplayMode {
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle("Treat multiple displays as one", isOn: $viewModel.combinedDisplayMode)
                                Text("When using multiple displays, treats them as a single display. Requires System Settings > Desktop & Dock > Displays have separate Spaces to be OFF.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // MARK: - Stacked Windows
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(NSLocalizedString("Offset window position on overlap", tableName: "Main", value: "", comment: ""), isOn: $viewModel.cyclingOverlapOffset)
                    Toggle(NSLocalizedString("Show stacked window list on hover", tableName: "Main", value: "", comment: ""), isOn: $viewModel.stackBadge)

                    HStack {
                        Text(NSLocalizedString("Toggle window list", tableName: "Main", value: "", comment: ""))
                        Spacer()
                        MASShortcutViewRepresentable(defaultsKey: StackBadgeManager.toggleDefaultsKey, validator: nil)
                            .frame(width: 160, height: 19)
                    }
                }
            } header: {
                Text(NSLocalizedString("Stacked Windows", tableName: "Main", value: "", comment: ""))
            }

            // MARK: - Side Split Ratios
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(NSLocalizedString("Horizontal (L/R, %)", tableName: "Main", value: "", comment: ""))
                        Spacer()

                        if viewModel.selectedHSplitPreset == nil {
                            TextField("", value: $viewModel.horizontalSplitRatio, formatter: Self.percentFormatter)
                                .frame(width: 45)
                                .multilineTextAlignment(.trailing)
                        }

                        Picker("", selection: Binding(
                            get: { viewModel.selectedHSplitPreset },
                            set: { viewModel.selectHSplitPreset($0) }
                        )) {
                            ForEach(CycleSize.sortedSizes, id: \.self) { size in
                                Text(size.title).tag(Optional(size))
                            }
                            Text(NSLocalizedString("Other", tableName: "Main", value: "", comment: "")).tag(Optional<CycleSize>.none)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    HStack {
                        Text(NSLocalizedString("Vertical (T/B, %)", tableName: "Main", value: "", comment: ""))
                        Spacer()

                        if viewModel.selectedVSplitPreset == nil {
                            TextField("", value: $viewModel.verticalSplitRatio, formatter: Self.percentFormatter)
                                .frame(width: 45)
                                .multilineTextAlignment(.trailing)
                        }

                        Picker("", selection: Binding(
                            get: { viewModel.selectedVSplitPreset },
                            set: { viewModel.selectVSplitPreset($0) }
                        )) {
                            ForEach(CycleSize.sortedSizes, id: \.self) { size in
                                Text(size.title).tag(Optional(size))
                            }
                            Text(NSLocalizedString("Other", tableName: "Main", value: "", comment: "")).tag(Optional<CycleSize>.none)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
            } header: {
                Text(NSLocalizedString("Side Split Ratio", tableName: "Main", value: "", comment: ""))
            }
            
            // MARK: - Stage Manager
            if viewModel.stageCapable {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Recent apps area")
                            Slider(
                                value: $viewModel.stageSize,
                                in: 0...400,
                                onEditingChanged: { editing in
                                    if !editing { viewModel.commitStageSize() }
                                }
                            )
                            Text("\(Int(viewModel.stageSize)) px")
                                .frame(width: 45, alignment: .trailing)
                        }
                        Text("If the area is too small, recent apps will be hidden")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Stage Manager")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .animation(.easeInOut(duration: 0.2), value: viewModel.todoEnabled)
        .animation(.easeInOut(duration: 0.2), value: viewModel.subsequentExecutionMode)
        .animation(.easeInOut(duration: 0.2), value: isMaximizeExpanded)
    }
}
