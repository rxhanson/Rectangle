import AppKit
import SwiftUI

class GeneralSettingsViewController: NSViewController {
    private var hostingController: NSHostingController<SettingsView>!

    override func viewDidLoad() {
        super.viewDidLoad()

        let swiftUIView = SettingsView()
        hostingController = NSHostingController(rootView: swiftUIView)
        
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

struct SettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            // General Section
            Section("General") {
                Toggle("Launch on login", isOn: $viewModel.launchOnLogin)
                
                Picker("Subsequent execution mode", selection: $viewModel.subsequentExecutionMode) {
                    ForEach(SubsequentExecutionMode.ordered, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                
                Toggle("Allow any shortcut", isOn: $viewModel.allowAnyShortcut)
                
                Toggle("Check for updates automatically", isOn: $viewModel.checkForUpdatesAutomatically)
                
                LabeledContent {
                    Button("Check for Updates") {
                        viewModel.checkForUpdates()
                    }
                } label: {
                    Text("Updates")
                }
            }

            // Gap Section
            Section("Gap") {
                LabeledContent("Gap size") {
                    HStack(spacing: 8) {
                        Slider(value: $viewModel.gapSize, in: 0...100, step: 1)
                        Text("\(Int(viewModel.gapSize)) px")
                            .monospacedDigit()
                            .frame(width: 45, alignment: .trailing)
                    }
                }

                if viewModel.gapSize > 0 {
                    Toggle("Skip gap top edge", isOn: $viewModel.skipGapTopEdge)
                }
            }

            // Window & Display Section
            Section("Window & Display") {
                Toggle("Move cursor across displays", isOn: $viewModel.moveCursorAcrossDisplays)
                
                if viewModel.useCursorScreenDetection {
                    Toggle("Use cursor screen detection", isOn: $viewModel.useCursorScreenDetection)
                }

                Toggle("Double click title bar", isOn: Binding(
                    get: { viewModel.doubleClickTitleBar != nil },
                    set: { newValue in
                        viewModel.requestDoubleClickTitleBarChange(to: newValue)
                    }
                ))

                Toggle("Treat multiple displays as one", isOn: $viewModel.combinedDisplayMode)
                Toggle("Green stoplight button maximizes instead of Full Screen", isOn: $viewModel.greenButtonOverride)
                Toggle("Preserve maximize state when moving across displays", isOn: $viewModel.autoMaximize)
                Toggle("Halves preserve other axis size", isOn: $viewModel.halvesPreserveOtherAxisSize)
                Toggle("Repeated maximize restores previous", isOn: $viewModel.repeatedMaximizeRestoresPrevious)
            }

            // Stage Section (Conditional)
            if StageUtil.stageCapable {
                Section("Stage") {
                    LabeledContent("Stage size") {
                        HStack(spacing: 8) {
                            Slider(value: $viewModel.stageSize, in: 0...500, step: 1)
                            Text("\(Int(viewModel.stageSize)) px")
                                .monospacedDigit()
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                }
            }

            // Cycle Sizes Section
            Section("Cycle Sizes") {
                ForEach(CycleSize.sortedSizes, id: \.self) { size in
                    Toggle(size.title, isOn: Binding(
                        get: { viewModel.selectedCycleSizes.contains(size) },
                        set: { isSelected in
                            if isSelected {
                                viewModel.selectedCycleSizes.insert(size)
                            } else {
                                viewModel.selectedCycleSizes.remove(size)
                            }
                        }
                    ))
                }

                Picker("Cyclic corner shortcuts expand", selection: $viewModel.cornerCycleExpansionAxis) {
                    ForEach(CornerCycleExpansionAxis.allCases, id: \.self) { axis in
                        Text(axis.title).tag(axis)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Resize adjacent windows when cycling side or corner shortcuts", isOn: $viewModel.cooperativeCornerResize)
            }

            // Todo Section
            Section("Todo") {
                Toggle("Enable Todo mode", isOn: $viewModel.todoMode)

                if viewModel.todoMode {
                    LabeledContent("Toggle Todo Shortcut") {
                        MASShortcutRepresentable(
                            defaultsKey: TodoManager.toggleDefaultsKey,
                            validator: TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey)
                        )
                        .frame(width: 130, height: 22)
                    }

                    LabeledContent("Reflow Todo Shortcut") {
                        MASShortcutRepresentable(
                            defaultsKey: TodoManager.reflowDefaultsKey,
                            validator: TodoShortcutValidator(defaultsKey: TodoManager.reflowDefaultsKey)
                        )
                        .frame(width: 130, height: 22)
                    }

                    LabeledContent("Sidebar width") {
                        HStack(spacing: 4) {
                            TextField("", value: $viewModel.todoSidebarWidth, formatter: NumberFormatter())
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)
                            
                            Picker("", selection: $viewModel.todoSidebarWidthUnit) {
                                ForEach(TodoSidebarWidthUnit.allCases, id: \.self) { unit in
                                    Text(unit.description).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    Picker("Sidebar side", selection: $viewModel.todoSidebarSide) {
                        ForEach(TodoSidebarSide.allCases, id: \.self) { side in
                            Text(side.title).tag(side)
                        }
                    }
                }
            }

            // Config Section
            Section("Configuration") {
                LabeledContent("Actions") {
                    HStack {
                        Button("Restore Defaults") {
                            viewModel.restoreDefaults()
                        }
                        Button("Export") {
                            viewModel.exportConfig()
                        }
                        Button("Import") {
                            viewModel.importConfig()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(minWidth: 500)
        .padding()
        .sheet(isPresented: $viewModel.showDoubleClickConflictAlert) {
            VStack(spacing: 16) {
                Text("Conflict with system setting")
                    .font(.headline)
                
                Text("To let Rectangle manage the title bar double click functionality, you need to disable the corresponding macOS setting.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("Close") {
                        viewModel.cancelDoubleClickTitleBarChange()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Open System Settings") {
                        viewModel.confirmDoubleClickTitleBarChange()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }
}
