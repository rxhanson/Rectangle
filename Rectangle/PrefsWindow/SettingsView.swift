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
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            // MARK: - App & Updates
            Section {
                Toggle("Launch on login", isOn: $viewModel.launchOnLogin)
                Toggle("Hide menu bar icon", isOn: $viewModel.hideMenuBarIcon)

                if viewModel.hideMenuBarIcon {
                    Text("When the menu bar icon is hidden, relaunch Rectangle from Finder to open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 18)
                }
            }
            
            Section {
                HStack {
                    Button(viewModel.hasPendingUpdate ? "Update Available…" : "Check for Updates…") {
                        viewModel.checkForUpdates()
                    }
                    Spacer()
                    Text(viewModel.versionString)
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Toggle("Check for updates automatically", isOn: $viewModel.checkForUpdatesAutomatically)
            }

            

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
                    .frame(width: 320)
                }

                if viewModel.subsequentExecutionMode.resizes {
                    VStack(alignment: .leading, spacing: 8) {
                        // Keep fraction choices as compact checkboxes
                        HStack(spacing: 12) {
                            ForEach(CycleSize.sortedSizes, id: \.self) { size in
                                Toggle(size.title, isOn: viewModel.binding(for: size))
                                    .toggleStyle(.checkbox)
                            }
                        }

                        HStack(spacing: 12) {
                            Text("Cyclic corner shortcuts expand:")
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Gaps between windows")
                        Slider(
                            value: $viewModel.gapSize,
                            in: 0...100,
                            step: 1,
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
                            .padding(.leading, 18)
                    }
                }

                Group {
                    Toggle("Remove keyboard shortcut restrictions", isOn: $viewModel.allowAnyShortcut)
                    Toggle("Move cursor along with window across displays", isOn: $viewModel.moveCursorAcrossDisplays)

                    if viewModel.showCursorScreenDetection {
                        Toggle("Use cursor screen detection", isOn: $viewModel.useCursorScreenDetection)
                    }

                    Toggle("Double-click window title bar to maximize/restore", isOn: $viewModel.doubleClickTitleBar)
                    Toggle("Preserve maximize state when moving across displays", isOn: $viewModel.autoMaximize)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Green stoplight button maximizes instead of Full Screen", isOn: $viewModel.greenButtonOverride)
                        Text("Hold any modifier key or use the window menu for default macOS behavior")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                    }

                    if viewModel.showCombinedDisplayMode {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Treat multiple displays as one", isOn: $viewModel.combinedDisplayMode)
                            Text("When using multiple displays, treats them as a single display. Requires System Settings > Desktop & Dock > Displays have separate Spaces to be OFF.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 18)
                        }
                    }
                }
                .toggleStyle(.switch)
            }

            // MARK: - Todo Mode
            Section {
                HStack {
                    Toggle("Show Todo Mode in menu", isOn: $viewModel.todoEnabled)
                        .toggleStyle(.switch)
                    Button(action: viewModel.showTodoModeHelp) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.todoEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keep a chosen application visible on the right of your primary screen at all times")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Todo app width")
                            
                            TextField("", value: $viewModel.todoSidebarWidth, format: .number)
                                .frame(width: 55)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { viewModel.commitTodoWidth() }

                            Picker("", selection: $viewModel.todoSidebarWidthUnit) {
                                Text("px").tag(TodoSidebarWidthUnit.pixels)
                                Text("%").tag(TodoSidebarWidthUnit.pct)
                            }
                            .frame(width: 65)

                            Spacer()

                            Text("Todo side")
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

            // MARK: - Stage Manager
            if viewModel.stageCapable {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Stage Manager recent apps area")
                            Slider(
                                value: $viewModel.stageSize,
                                in: 0...400,
                                step: 1,
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
                }
            }

            // MARK: - Footer Actions
            Section {
                HStack {
                    Button("Restore Default Shortcuts & Snap Areas") {
                        viewModel.restoreDefaults()
                    }

                    Spacer()

                    Button {
                        viewModel.importConfig()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        viewModel.exportConfig()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    Button("Extras") {
                        viewModel.showExtrasPopover()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 600)
        .animation(.easeInOut(duration: 0.2), value: viewModel.todoEnabled)
        .animation(.easeInOut(duration: 0.2), value: viewModel.subsequentExecutionMode)
    }
}
