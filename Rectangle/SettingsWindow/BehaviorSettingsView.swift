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
@MainActor
struct BehaviorSettingsView: View {
    @State private var viewModel = BehaviorSettingsViewModel()
    
    // Popover state
    @State private var showTodoInfoPopover = false
    @State private var showingLayoutHelperExample = false

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
                            Text("Cyclic corner shortcuts expand")
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
                VStack(alignment: .leading, spacing: 8) {
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
            
            
            // MARK: - Maximize
            Section {
                CustomDisclosureGroup {
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
                CustomDisclosureGroup {
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
                CustomDisclosureGroup {
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
                CustomDisclosureGroup {
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
            
            // MARK: - Todo Mode
            Section {
                CustomDisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        
                        Toggle("Show Todo Mode in menu", isOn: $viewModel.todoEnabled)
                        
                        // Dynamically show/hide the controls based on toggle state
                        if viewModel.todoEnabled {
                            VStack(alignment: .leading, spacing: 10) {
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
                            .transition(.opacity)
                        }
                    }
                    .padding(.leading, 12)
                } label: {
                    HStack(spacing: 6) {
                        Label("Todo Mode", systemImage: "list.bullet.rectangle.portrait")
                        
                        Button(action: { showTodoInfoPopover.toggle() }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showTodoInfoPopover, arrowEdge: .trailing) {
                            TodoModeInfoView()
                        }
                    }
                }
            }
            
            layoutHelperSection

            // MARK: - Stage Manager
            if viewModel.stageCapable {
                Section {
                    CustomDisclosureGroup {
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
                CustomDisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        Toggle("Animate windows", isOn: $viewModel.experimentalAnimations)
                        Toggle("Preserve side axis size for half actions, similar to Windows", isOn: $viewModel.halvesPreserveOtherAxisSize)
                        Toggle("Show warning when windows cannot be resized small enough", isOn: $viewModel.showMinimumWindowSizeWarning)
                        Toggle("Show *Extra* shortcuts in menu", isOn: $viewModel.showAdditionalSizesInMenu)
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
    }
    private var layoutHelperSection: some View {
        Section {
            CustomDisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Layout Helper", isOn: $viewModel.layoutHelper)
                            .disabled(viewModel.stageManagerEnabled)
                            .accessibilityIdentifier("layoutHelper")
                        if viewModel.stageManagerEnabled {
                            Text("Layout Helper is unavailable while Stage Manager is enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Show close button", isOn: $viewModel.layoutHelperCloseButton)
                        .disabled(!viewModel.layoutHelper || viewModel.stageManagerEnabled)
                        .accessibilityIdentifier("layoutHelperCloseButton")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Show Layout Helper for")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Keyboard and menu snaps", isOn: $viewModel.layoutHelperKeyboard)
                                .disabled(!viewModel.layoutHelper || viewModel.stageManagerEnabled)
                            Toggle("Grids with eight or more cells", isOn: $viewModel.layoutHelperDenseGrids)
                                .disabled(!viewModel.layoutHelper || viewModel.stageManagerEnabled)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Drag dividers to resize adjacent windows", isOn: $viewModel.windowDivider)
                            .accessibilityIdentifier("windowDivider")
                        Text("Left/right and top/bottom pairs only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Enhanced transitions", isOn: $viewModel.windowDividerEnhanced)
                            .accessibilityIdentifier("windowDividerEnhanced")
                        Text("Uses a temporary screenshot to hide resizing. Requires Screen Recording access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                    .disabled(!viewModel.windowDivider || !LayoutHelperPermission.previewsSupported)
                    if viewModel.layoutHelper {
                        if !LayoutHelperPermission.previewsSupported {
                            Text("Window thumbnails require macOS 14 or later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if viewModel.previewPermissionAllowed {
                            Text("Window thumbnails enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Enable previews…") { viewModel.enablePreviews() }
                                .disabled(viewModel.stageManagerEnabled)
                            Text("Thumbnails need Screen Recording access. Icons and titles work without it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 12)
            } label: {
                HStack(spacing: 6) {
                    Label("Layout Helper", systemImage: "rectangle.3.group")
                    Button(action: { showingLayoutHelperExample.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Layout Helper example")
                    .popover(isPresented: $showingLayoutHelperExample, arrowEdge: .trailing) {
                        LayoutHelperExampleView()
                    }
                }
            }
        }
    }

}

// MARK: - Todo Mode Info Popover View
// MARK: - Layout Helper Example
/// A self-contained illustration. No screen capture, input injection, or real window movement.
private struct LayoutHelperExampleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var scene = Scene()

    private struct Scene {
        var notes = CGRect(x: 0.27, y: 0.20, width: 0.49, height: 0.65)
        var research = CGRect(x: 0.58, y: 0.11, width: 0.33, height: 0.35)
        var pointer = CGPoint(x: 0.68, y: 0.76)
        var pointerOpacity = 1.0
        var pressOpacity = 0.0
        var previewOpacity = 0.0
        var helperOpacity = 0.0
        var researchOpacity = 0.0
        var tasksOpacity = 0.0
        var hoverOpacity = 0.0
    }

    private let left = CGRect(x: 0.02, y: 0.04, width: 0.47, height: 0.92)
    private let right = CGRect(x: 0.51, y: 0.04, width: 0.47, height: 0.92)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snap a window. Choose its neighbor.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.20, green: 0.24, blue: 0.33), Color(red: 0.20, green: 0.29, blue: 0.27)]
                            : [Color(red: 0.88, green: 0.90, blue: 0.95), Color(red: 0.82, green: 0.89, blue: 0.87)],
                        startPoint: .topTrailing, endPoint: .bottomLeading)
                    LayoutHelperExampleSurface(cornerRadius: 10)
                        .modifier(ExamplePlacement(rect: right, size: geometry.size))
                        .opacity(scene.helperOpacity)
                    LayoutHelperExampleSurface(cornerRadius: 9, decorated: true)
                        .modifier(ExamplePlacement(rect: left, size: geometry.size))
                        .opacity(scene.previewOpacity)
                    window("Notes", accent: .blue)
                        .modifier(ExamplePlacement(rect: scene.notes, size: geometry.size))
                    window("Research", accent: .blue)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.blue.opacity(scene.hoverOpacity * 0.6), lineWidth: 1.5))
                        .modifier(ExamplePlacement(rect: scene.research, size: geometry.size))
                        .opacity(scene.researchOpacity)
                    window("Tasks", accent: .green)
                        .modifier(ExamplePlacement(
                            rect: CGRect(x: 0.58, y: 0.54, width: 0.33, height: 0.35), size: geometry.size))
                        .opacity(scene.tasksOpacity)
                    ZStack(alignment: .topLeading) {
                        Circle().fill(.primary.opacity(0.12))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                            .frame(width: 25, height: 25)
                            .offset(x: -10, y: -10)
                            .opacity(scene.pressOpacity)
                        Image(nsImage: NSCursor.arrow.image)
                    }
                    .fixedSize()
                    .offset(x: geometry.size.width * scene.pointer.x,
                            y: geometry.size.height * scene.pointer.y)
                    .opacity(scene.pointerOpacity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .frame(height: 291)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drag Notes to the left edge, then choose Research in Layout Helper to fill the right side.")
        }
        .padding(20)
        .frame(width: 520)
        .task(id: reduceMotion) { await demonstrate() }
    }

    private struct ExamplePlacement: ViewModifier {
        let rect: CGRect
        let size: CGSize
        func body(content: Content) -> some View {
            content.frame(width: size.width * rect.width, height: size.height * rect.height)
                .offset(x: size.width * rect.minX, y: size.height * rect.minY)
        }
    }

    private func window(_ title: LocalizedStringKey, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().fill(.secondary.opacity(0.4)).frame(width: 4, height: 4)
                    }
                }
                Text(title).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).frame(height: 25)
            .background(.primary.opacity(0.025))
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(index == 0 ? accent.opacity(0.55) : Color.secondary.opacity(0.12))
                            .frame(width: max(0, geometry.size.width * (index == 0 ? 0.54 : 0.85)),
                                   height: index == 0 ? 5 : 4)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    @MainActor private func demonstrate() async {
        scene = Scene()
        if reduceMotion {
            scene.notes = left
            scene.research = right
            scene.researchOpacity = 1
            scene.pointerOpacity = 0
            return
        }
        // Play the example once at 1.6x speed; dismissal cancels the remaining cues.
        let duration = 7.2 / 1.6
        let cues: [(start: Double, length: Double, update: () -> Void)] = [
            (0, 0.13, { scene.pointer = CGPoint(x: 0.45, y: 0.23) }),
            (0.15, 0.03, { scene.pressOpacity = 1 }),
            (0.19, 0.18, {
                scene.pointer = CGPoint(x: 0.03, y: 0.23)
                scene.notes.origin.x = -0.15
            }),
            (0.31, 0.06, { scene.previewOpacity = 1 }),
            (0.40, 0.03, { scene.pressOpacity = 0 }),
            (0.42, 0.09, { scene.notes = left }),
            (0.49, 0.03, { scene.previewOpacity = 0 }),
            (0.50, 0.06, { scene.helperOpacity = 1; scene.researchOpacity = 1 }),
            (0.52, 0.06, { scene.tasksOpacity = 1 }),
            (0.52, 0.12, { scene.pointer = CGPoint(x: 0.74, y: 0.28) }),
            (0.62, 0.04, { scene.hoverOpacity = 1 }),
            (0.68, 0.02, { scene.pressOpacity = 1 }),
            (0.70, 0.05, { scene.pressOpacity = 0 }),
            (0.72, 0.12, { scene.research = right }),
            (0.72, 0.07, { scene.tasksOpacity = 0 }),
            (0.73, 0.10, { scene.helperOpacity = 0 }),
            (0.74, 0.03, { scene.hoverOpacity = 0 }),
            (0.79, 0.08, { scene.pointerOpacity = 0 })
        ]
        let clock = ContinuousClock()
        let start = clock.now
        do {
            for cue in cues {
                try await clock.sleep(until: start.advanced(by: .seconds(cue.start * duration)))
                try Task.checkCancellation()
                withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: cue.length * duration)) {
                    cue.update()
                }
            }
        } catch is CancellationError {
            // Closing the popover cancels pending cues; reopening starts from the beginning.
        } catch { }
    }
}

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
