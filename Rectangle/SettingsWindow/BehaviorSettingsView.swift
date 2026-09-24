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
    
    // Disclosure states
    @State private var isMaximizeExpanded = false
    @State private var isStackedWindowsExpanded = false
    @State private var isSideSplitRatiosExpanded = false
    @State private var isStageManagerExpanded = false
    @State private var isAcrossDisplaysExpanded = false
    @State private var isExtrasExpanded = false
    
    // Popover state
    @State private var showTodoInfoPopover = false

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
            
            // MARK: - Todo Mode
            Section {
                HStack {
                    Toggle(isOn: $viewModel.todoEnabled) {
                        HStack(spacing: 4) {
                            Text("Show Todo Mode in menu")
                            Button(action: { showTodoInfoPopover.toggle() }) {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showTodoInfoPopover, arrowEdge: .trailing) {
                                TodoModeInfoView()
                            }
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
                    .padding(.leading, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            // MARK: - Maximize (Disclosure Section)
            Section {
                DisclosureGroup(isExpanded: $isMaximizeExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        if viewModel.showCursorScreenDetection {
                            Toggle("Use cursor screen detection", isOn: $viewModel.useCursorScreenDetection)
                        }
                        
                        Toggle("Double-click window title bar to maximize/restore", isOn: $viewModel.doubleClickTitleBar)
                        Toggle("Repeated maximize restores the previous size and position", isOn: $viewModel.repeatedMaximizeRestoresPrevious)

                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Green stoplight button maximizes instead of Full Screen", isOn: $viewModel.greenButtonOverride)
                            Text("Hold any modifier key or use the window menu for default macOS behavior")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 12)
                } label: {
                    Label("Maximize Settings", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }

            // MARK: - Across Display Settings
            Section {
                DisclosureGroup(isExpanded: $isAcrossDisplaysExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        Toggle("Move cursor along with window across displays", isOn: $viewModel.moveCursorAcrossDisplays)
                        Toggle("Preserve maximize state when moving across displays", isOn: $viewModel.autoMaximize)
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Center windows when moving across displays", isOn: $viewModel.centerAcrossDisplays)
                            Text("When off, window-to-screen edges are preserved where applicable.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 12)
                } label: {
                    Label("Across Display Settings", systemImage: "display.2")
                }
            }

            // MARK: - Stacked Windows
            Section {
                DisclosureGroup(isExpanded: $isStackedWindowsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Offset window position on overlap", isOn: $viewModel.cyclingOverlapOffset)
                            Text("This leaves a little space showing the window below and is best with gaps between windows")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Show stacked window list on hover", isOn: $viewModel.stackBadge)
                            Text("Hover cursor near the top left corner of a window to show the list")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Toggle window list")
                            Spacer()
                            MASShortcutViewRepresentable(defaultsKey: StackBadgeManager.toggleDefaultsKey, validator: nil)
                                .frame(width: 160, height: 24)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 12)
                } label: {
                    Label("Stacked Windows", systemImage: "square.on.square")
                }
            }

            // MARK: - Side Split Ratios
            Section {
                DisclosureGroup(isExpanded: $isSideSplitRatiosExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                        Text("Configure the divide between side and corner actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("Horizontal (L/R, %)")
                            Spacer()

                            if viewModel.selectedHSplitPreset == nil {
                                TextField("", value: $viewModel.horizontalSplitRatio, formatter: Self.percentFormatter)
                                    .multilineTextAlignment(.trailing)
                            }

                            Picker("", selection: Binding(
                                get: { viewModel.selectedHSplitPreset },
                                set: { viewModel.selectHSplitPreset($0) }
                            )) {
                                ForEach(CycleSize.sortedSizes, id: \.self) { size in
                                    Text(size.title).tag(Optional(size))
                                }
                                Text("Other").tag(Optional<CycleSize>.none)
                            }
                            .labelsHidden()
                        }

                        HStack {
                            Text("Vertical (T/B, %)")
                            Spacer()

                            if viewModel.selectedVSplitPreset == nil {
                                TextField("", value: $viewModel.verticalSplitRatio, formatter: Self.percentFormatter)
                                    .multilineTextAlignment(.trailing)
                            }

                            Picker("", selection: Binding(
                                get: { viewModel.selectedVSplitPreset },
                                set: { viewModel.selectVSplitPreset($0) }
                            )) {
                                ForEach(CycleSize.sortedSizes, id: \.self) { size in
                                    Text(size.title).tag(Optional(size))
                                }
                                Text("Other").tag(Optional<CycleSize>.none)
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 12)
                } label: {
                    Label("Side Split Ratio", systemImage: "rectangle.split.2x1")
                }
            }
            
            // MARK: - Stage Manager
            if viewModel.stageCapable {
                Section {
                    DisclosureGroup(isExpanded: $isStageManagerExpanded) {
                        VStack(alignment: .leading, spacing: 4) {
                            Divider()
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
                        .padding(.top, 4)
                        .padding(.leading, 12)
                    } label: {
                        Label("Stage Manager", systemImage: "squares.leading.rectangle")
                    }
                }
            }
            
            // MARK: - Extras
            Section {
                DisclosureGroup(isExpanded: $isExtrasExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        Toggle("Preserve side axis size for half actions, similar to Windows", isOn: $viewModel.halvesPreserveOtherAxisSize)
                        Toggle("Animate windows (experimental)", isOn: $viewModel.experimentalAnimations)
                        Toggle("Show Extra shortcuts in menu", isOn: $viewModel.showAdditionalSizesInMenu)
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
                    .padding(.leading, 12)
                } label: {
                    Label("Extras", systemImage: "ellipsis.viewfinder")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .animation(.easeInOut(duration: 0.2), value: viewModel.todoEnabled)
        .animation(.easeInOut(duration: 0.2), value: viewModel.subsequentExecutionMode)
        .animation(.easeInOut(duration: 0.2), value: isMaximizeExpanded)
        .animation(.easeInOut(duration: 0.2), value: isStackedWindowsExpanded)
        .animation(.easeInOut(duration: 0.2), value: isSideSplitRatiosExpanded)
        .animation(.easeInOut(duration: 0.2), value: isStageManagerExpanded)
        .animation(.easeInOut(duration: 0.2), value: isAcrossDisplaysExpanded)
        .animation(.easeInOut(duration: 0.2), value: isExtrasExpanded)
    }
}

// MARK: - Todo Mode Info Popover View
struct TodoModeInfoView: View {
    // Structural data wrapper to hold LocalizedStringKey
    private struct Step: Identifiable {
        let id: Int
        let number: String
        let text: LocalizedStringKey
    }

    private let steps: [Step] = [
        Step(id: 1, number: "1.", text: "Bring your chosen todo application frontmost"),
        Step(id: 2, number: "2.", text: "In the Rectangle menu, select\n\"Use [Application] as Todo App\""),
        Step(id: 3, number: "3.", text: "In the Rectangle menu, enable Todo Mode.")
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("About Todo Mode")
                .font(.title2)
                .bold()

            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)

            Text("Keep a chosen application visible on the right side of your primary screen at all times")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // MARK: - Formatted Steps
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Text(step.number)
                            .font(.body)
                            .bold()
                            .foregroundColor(.accentColor)

                        Text(step.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("While in Todo Mode, you can refresh the Todo Mode layout by selecting \"Reflow Todo\" in the Rectangle menu or executing the associated keyboard shortcut.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(20)
        .frame(width: 330)
    }
}
