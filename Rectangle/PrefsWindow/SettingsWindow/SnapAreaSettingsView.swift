/// SnapAreaView.swift

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
    
    @Published var experimentalAnimations: Bool = false {
        didSet {
            guard oldValue != experimentalAnimations else { return }
            Defaults.experimentalWindowAnimations.enabled = experimentalAnimations
            Notification.Name.windowAnimationPreferencesChanged.post()
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

    // Displays / UI State
    @Published var isPortraitConnected: Bool = NSScreen.portraitDisplayConnected
    @Published var isLandscapePopoverPresented: Bool = false
    @Published var isPortraitPopoverPresented: Bool = false

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
        experimentalAnimations = Defaults.experimentalWindowAnimations.enabled
        blurAppearance = Defaults.blurAppearance.value
        missionControlDraggingDisabled = Defaults.missionControlDragging.userDisabled
        isPortraitConnected = NSScreen.portraitDisplayConnected
    }

    private func setupNotificationObservers() {
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

    private var landscapeButtonTitle: String {
        viewModel.isPortraitConnected ? "Landscape Snap Areas…" : "Configure Snap Areas…"
    }

    var body: some View {
        Form {
            
            Section {
                HStack {
                    Button(action: { viewModel.isLandscapePopoverPresented.toggle() }) {
                        Label(landscapeButtonTitle, systemImage: "rectangle.inset.filled")
                    }
                    .popover(isPresented: $viewModel.isLandscapePopoverPresented, arrowEdge: .bottom) {
                        SnapAreaGridPopoverView(viewModel: viewModel, orientation: .landscape)
                            .padding()
                            .frame(width: 520, height: 380)
                    }

                    if viewModel.isPortraitConnected {
                        Spacer()
                        Button(action: { viewModel.isPortraitPopoverPresented.toggle() }) {
                            Label("Portrait Snap Areas…", systemImage: "rectangle.portrait.inset.filled")
                        }
                        .popover(isPresented: $viewModel.isPortraitPopoverPresented, arrowEdge: .bottom) {
                            SnapAreaGridPopoverView(viewModel: viewModel, orientation: .portrait)
                                .padding()
                                .frame(width: 380, height: 520)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section {
                Toggle("Snap windows by dragging", isOn: $viewModel.windowSnapping)
                Toggle("Restore window size when unsnapped", isOn: $viewModel.unsnapRestore)
            }
            
            Section {
                Toggle("Provide haptic feedback", isOn: $viewModel.hapticFeedback)
                Toggle("Animate footprint", isOn: $viewModel.animateFootprint)
                Toggle("Animate windows (experimental)", isOn: $viewModel.experimentalAnimations)
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

        }
        .formStyle(.grouped)
        .frame(minHeight: 400)
        .frame(width: 500)
        .animation(.easeInOut(duration: 0.2), value: viewModel.footprintBlur)
    }
}

// MARK: - Popover Snap Area Grid Layout

struct SnapAreaGridPopoverView: View {
    @ObservedObject var viewModel: SnapAreaViewModel
    let orientation: DisplayOrientation

    private var headerTitle: String {
        if orientation == .portrait {
            return "Portrait Snap Areas"
        } else {
            return viewModel.isPortraitConnected ? "Landscape Snap Areas" : "Snap Areas"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(headerTitle)
                .font(.headline)

            VStack(spacing: 12) {
                // Top Row
                HStack(spacing: 8) {
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .tl)
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .t)
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .tr)
                }

                // Middle Row
                HStack(spacing: 12) {
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .l)

                    // Display Graphic
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                        )
                        .aspectRatio(orientation == .landscape ? 16 / 10 : 10 / 16, contentMode: .fit)

                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .r)
                }

                // Bottom Row
                HStack(spacing: 8) {
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .bl)
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .b)
                    SnapAreaPicker(viewModel: viewModel, orientation: orientation, directional: .br)
                }
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
                        Text(name).tag(action.rawValue)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
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
