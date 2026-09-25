/// SnapAreaSettingsView.swift

import SwiftUI
import Combine

class SnapAreaSettingsViewController: NSViewController {
    private var hostingController: NSHostingController<SnapAreaSettingsView>!

    override func viewDidLoad() {
        super.viewDidLoad()

        let swiftUIView = SnapAreaSettingsView()
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

// MARK: - ViewModel

final class SnapAreaViewModel: ObservableObject {
    // General Settings
    @Published var windowSnapping: Bool = true {
        didSet {
            guard oldValue != windowSnapping else { return }
            Defaults.windowSnapping.enabled = windowSnapping
            Notification.Name.windowSnapping.post(object: windowSnapping)
            if windowSnapping {
                MacTilingDefaults.checkForBuiltInTiling(skipIfAlreadyNotified: false)
            }
        }
    }
    
    @Published var unsnapRestore: Bool = true {
        didSet {
            Defaults.unsnapRestore.enabled = unsnapRestore
        }
    }
    
    @Published var hapticFeedback: Bool = false {
        didSet {
            Defaults.hapticFeedbackOnSnap.enabled = hapticFeedback
        }
    }
    
    @Published var animateFootprint: Bool = true {
        didSet {
            let val: Float = animateFootprint ? 0.75 : 0.0
            Defaults.footprintAnimationDurationMultiplier.value = val
        }
    }
    
    @Published var footprintBlur: Bool = false {
        didSet {
            Defaults.footprintBlur.enabled = footprintBlur
        }
    }

    @Published var blurAppearance: BlurAppearance = .system {
        didSet {
            Defaults.blurAppearance.value = blurAppearance
        }
    }
    
    @Published var missionControlDraggingDisabled: Bool = false {
        didSet {
            Defaults.missionControlDragging.enabled = !missionControlDraggingDisabled
            Notification.Name.missionControlDragging.post(object: !missionControlDraggingDisabled)
        }
    }

    @Published var layoutHelper = false {
        didSet {
            guard oldValue != layoutHelper else { return }
            Defaults.layoutHelper.enabled = layoutHelper
            LayoutHelperManager.shared.cancel()
            if layoutHelper { LayoutHelperPermission.guideIfNeeded { [weak self] in self?.refreshPreviewPermission() } }
        }
    }
    @Published var layoutHelperKeyboard = false {
        didSet {
            Defaults.layoutHelperKeyboard.enabled = layoutHelperKeyboard
            LayoutHelperManager.shared.cancel()
        }
    }
    @Published var layoutHelperDenseGrids = false {
        didSet {
            Defaults.layoutHelperDenseGrids.enabled = layoutHelperDenseGrids
            LayoutHelperManager.shared.cancel()
        }
    }
    @Published var stageManagerEnabled = false
    @Published var previewPermissionAllowed = false
    private var stageObservation: NSObject?

    func refreshPreviewPermission() { previewPermissionAllowed = LayoutHelperPermission.previewsAllowed }
    func enablePreviews() {
        LayoutHelperManager.shared.cancel()
        LayoutHelperPermission.guideIfNeeded { [weak self] in self?.refreshPreviewPermission() }
    }

    // Displays / UI State
    @Published var isPortraitConnected: Bool = NSScreen.portraitDisplayConnected

    private var cancellables = Set<AnyCancellable>()

    init() {
        syncDefaults()
        setupNotificationObservers()
    }

    func syncDefaults() {
        windowSnapping = !Defaults.windowSnapping.userDisabled
        unsnapRestore = !Defaults.unsnapRestore.userDisabled
        hapticFeedback = Defaults.hapticFeedbackOnSnap.userEnabled
        animateFootprint = Defaults.footprintAnimationDurationMultiplier.value > 0
        footprintBlur = Defaults.footprintBlur.enabled
        blurAppearance = Defaults.blurAppearance.value
        missionControlDraggingDisabled = Defaults.missionControlDragging.userDisabled
        layoutHelper = Defaults.layoutHelper.userEnabled
        layoutHelperKeyboard = Defaults.layoutHelperKeyboard.enabled
        layoutHelperDenseGrids = Defaults.layoutHelperDenseGrids.enabled
        stageManagerEnabled = StageUtil.stageCapable && StageUtil.stageEnabled
        refreshPreviewPermission()
        isPortraitConnected = NSScreen.portraitDisplayConnected
    }

    private func setupNotificationObservers() {
        stageObservation = StageUtil.observeEnabled { [weak self] in
            self?.stageManagerEnabled = StageUtil.stageCapable && StageUtil.stageEnabled
        }
        let center = NotificationCenter.default

        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.isPortraitConnected = NSScreen.portraitDisplayConnected
            }
            .store(in: &cancellables)

        center.publisher(for: .configImported)
            .sink { [weak self] _ in
                self?.syncDefaults()
            }
            .store(in: &cancellables)

        center.publisher(for: .windowSnapping)
            .sink { [weak self] _ in
                self?.windowSnapping = !Defaults.windowSnapping.userDisabled
            }
            .store(in: &cancellables)
    }

    // Snap Area Handlers
    func getSelectedTag(for directional: Directional, orientation: DisplayOrientation) -> Int {
        let snapAreaConfig = orientation == .landscape
            ? SnapAreaModel.instance.landscape[directional]
            : SnapAreaModel.instance.portrait[directional]

        return snapAreaConfig?.action?.rawValue ?? snapAreaConfig?.compound?.rawValue ?? -1
    }

    func updateSnapArea(selectedTag: Int, directional: Directional, orientation: DisplayOrientation) {
        var snapAreaConfig: SnapAreaConfig?
        if selectedTag < -1, let compound = CompoundSnapArea(rawValue: selectedTag) {
            snapAreaConfig = SnapAreaConfig(compound: compound)
        } else if selectedTag > -1, let action = WindowAction(rawValue: selectedTag) {
            snapAreaConfig = SnapAreaConfig(action: action)
        }
        SnapAreaModel.instance.setConfig(type: orientation, directional: directional, snapAreaConfig: snapAreaConfig)
    }
}

// MARK: - Main Snap Area View

struct SnapAreaSettingsView: View {
    @StateObject private var viewModel = SnapAreaViewModel()
    @State private var showingLayoutHelperExample = false

    private var landscapeHeaderTitle: String {
        viewModel.isPortraitConnected ? String(localized: "Landscape Snap Areas") : String(localized: "Snap Areas")
    }

    var body: some View {
        Form {
            // General Toggles
            Section {
                Toggle("Snap windows by dragging", isOn: $viewModel.windowSnapping)
                Toggle("Restore window size when unsnapped", isOn: $viewModel.unsnapRestore)
            }

            // Customization Options
             Section {
                Toggle("Haptic feedback", isOn: $viewModel.hapticFeedback)
                Toggle("Animate footprint", isOn: $viewModel.animateFootprint)
                Toggle("Blur footprint", isOn: $viewModel.footprintBlur)


                if viewModel.footprintBlur {
                    Picker("Blur appearance", selection: $viewModel.blurAppearance) {
                        Text("Follow System").tag(BlurAppearance.system)
                        Text("Light").tag(BlurAppearance.light)
                        Text("Dark").tag(BlurAppearance.dark)
                    }
                }

                if viewModel.missionControlDraggingDisabled {
                    Toggle("Mission Control dragging", isOn: $viewModel.missionControlDraggingDisabled)
                }
            }

            Section {
                HStack {
                    Toggle("Layout Helper", isOn: $viewModel.layoutHelper)
                        .disabled(viewModel.stageManagerEnabled)
                        .accessibilityIdentifier("layoutHelper")
                    Spacer()
                    Button("See example…") { showingLayoutHelperExample = true }
                        .popover(isPresented: $showingLayoutHelperExample) {
                            VStack(alignment: .leading, spacing: 12) {
                                Image("LayoutHelperExample")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Layout Helper example: Notes is snapped on the left; choose Research or Tasks to fill the right side.")
                                Text("Snap a window, then choose another to fill the remaining space. Thumbnails need Screen Recording access.")
                            }
                            .padding(16)
                            .frame(width: 592)
                        }
                }
                Text("Layout Helper will be disabled when Stage Manager is enabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Keyboard and menu snaps", isOn: $viewModel.layoutHelperKeyboard)
                    .disabled(!viewModel.layoutHelper || viewModel.stageManagerEnabled)
                Toggle("Grids with eight or more cells", isOn: $viewModel.layoutHelperDenseGrids)
                    .disabled(!viewModel.layoutHelper || viewModel.stageManagerEnabled)
                if viewModel.layoutHelper {
                    if !LayoutHelperPermission.previewsSupported {
                        Text("Window thumbnails require macOS 14 or later.")
                    } else if viewModel.previewPermissionAllowed {
                        Text("Window thumbnails enabled.")
                    } else {
                        Button("Enable previews…") { viewModel.enablePreviews() }
                            .disabled(viewModel.stageManagerEnabled)
                        Text("Thumbnails need Screen Recording access. Icons and titles work without it.")
                    }
                }
            } header: {
                Label("Layout Helper", systemImage: "rectangle.on.rectangle")
            }
            
            // Landscape Inline Section
            Section {
                SnapAreaGridView(viewModel: viewModel, orientation: .landscape)
            } header: {
                Label(landscapeHeaderTitle, systemImage: "rectangle.inset.filled")
                    .font(.headline)
            }

            // Portrait Inline Section (Only visible if portrait monitor connected)
            if viewModel.isPortraitConnected {
                Section {
                    SnapAreaGridView(viewModel: viewModel, orientation: .portrait)
                } header: {
                    Label("Portrait Snap Areas", systemImage: "rectangle.portrait.inset.filled")
                        .font(.headline)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 400)
        .frame(width: 500)
        .animation(.easeInOut(duration: 0.2), value: viewModel.footprintBlur)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPortraitConnected)
    }
}

// MARK: - Grid Snap Area Layout

struct SnapAreaGridView: View {
    @ObservedObject var viewModel: SnapAreaViewModel
    let orientation: DisplayOrientation

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 12) {
            // Top Row
            GridRow(alignment: .center) {
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .tl)
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .t)
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .tr)
            }

            // Middle Row
            GridRow(alignment: .center) {
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .l)

                // Display Graphic Representation (Center Cell)
                MacDesktopGraphic(orientation: orientation)

                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .r)
            }

            // Bottom Row
            GridRow(alignment: .center) {
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .bl)
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .b)
                SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .br)
            }
        }
    }
}

// MARK: - Individual Snap Area Menu Picker

struct SnapAreaPicker: View {
    @ObservedObject var viewModel: SnapAreaViewModel
    let orientation: DisplayOrientation
    let directional: Directional

    @State private var selectedTag: Int = -1

    private var pickerAlignment: Alignment {
        switch directional {
        case .tl, .l, .bl:
            return .trailing
        case .t, .b, .c:
            return .center
        case .tr, .r, .br:
            return .leading
        }
    }

    var body: some View {
        Picker("", selection: $selectedTag) {
            Text("-").tag(-1)

            Section {
                ForEach(CompoundSnapArea.all.filter {
                    $0.compatibleOrientation.contains(orientation) && $0.compatibleDirectionals.contains(directional)
                }, id: \.rawValue) { compound in
                    Text(compound.displayName).tag(compound.rawValue)
                }
            }

            Section {
                ForEach(WindowAction.active.filter { $0.isDragSnappable }, id: \.rawValue) { action in
                    if let name = action.displayName {
                        Label {
                            Text(name)
                        } icon: {
                            Image(nsImage: action.image.resizedForMenu())
                        }
                        .tag(action.rawValue)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: pickerAlignment)
        .onAppear {
            selectedTag = viewModel.getSelectedTag(for: directional, orientation: orientation)
        }
        .onChange(of: selectedTag) { oldTag, newTag in
            viewModel.updateSnapArea(selectedTag: newTag, directional: directional, orientation: orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .defaultSnapAreas)) { _ in
            selectedTag = viewModel.getSelectedTag(for: directional, orientation: orientation)
        }
    }
}

extension NSImage {
    func resizedForMenu(targetHeight: CGFloat = 14) -> NSImage {
        guard size.height > 0 else { return self }
        
        let aspectRatio = size.width / size.height
        let copy = self.copy() as! NSImage
        copy.size = NSSize(width: targetHeight * aspectRatio, height: targetHeight)
        return copy
    }
}

// MARK: - Mac Desktop Display Graphic

struct MacDesktopGraphic: View {
    let orientation: DisplayOrientation

    var body: some View {
        ZStack {
            // Main Display Background
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.12))

            // Screen Content (Menu Bar & Dock)
            VStack(spacing: 0) {
                // Menu Bar
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: 5)
                    .overlay(
                        HStack(spacing: 2) {
                            // Apple Logo Dot
                            Circle()
                                .fill(Color.primary.opacity(0.4))
                                .frame(width: 2, height: 2)

                            // Menu Text Placeholders (Mini Lines)
                            Capsule()
                                .fill(Color.primary.opacity(0.4))
                                .frame(width: 5, height: 1.2)

                            Capsule()
                                .fill(Color.primary.opacity(0.25))
                                .frame(width: 4, height: 1.2)

                            Capsule()
                                .fill(Color.primary.opacity(0.25))
                                .frame(width: 4, height: 1.2)

                            Spacer()

                            // Right-Side Status Items
                            Capsule()
                                .fill(Color.primary.opacity(0.25))
                                .frame(width: 3, height: 1.2)

                            Capsule()
                                .fill(Color.primary.opacity(0.25))
                                .frame(width: 3, height: 1.2)
                        }
                        .padding(.horizontal, 3)
                    )

                Spacer()

                // Dock
                let iconCount = orientation == .portrait ? 4 : 6

                HStack(spacing: 1.5) {
                    ForEach(0..<iconCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.2)
                            .fill(Color.primary.opacity(0.35))
                            .frame(maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .padding(.horizontal, 2.5)
                .padding(.vertical, 1)
                .frame(height: 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.primary.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                )
                .padding(.bottom, 3)
            }

            // Screen Border Overlay
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(
            width: orientation == .portrait ? 62.5 : 100,
            height: orientation == .portrait ? 100 : 62.5
        )
        .frame(width: 100, height: 100)
        .gridCellAnchor(.center)
    }
}
