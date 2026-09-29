import SwiftUI

struct TrackpadGestureSettingsView: View {
    @Bindable private var manager = TrackpadGestureManager.shared
    @State private var showingGestureExample = false
    private let directions: [TrackpadDirection] = [.up, .down, .left, .right]
    private let groups: [WindowActionCategory] = [.halves, .corners, .thirds, .fourths, .sixths, .eighths,
        .ninths, .twelfths, .sixteenths, .size, .display, .move, .other]
    private var showsWarning: Bool { manager.settings.enabled && manager.status != nil }

    var body: some View {
        Section {
            CustomDisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    Toggle("Trackpad gestures", isOn: Binding(
                        get: { manager.settings.enabled }, set: { manager.setEnabledByUser($0) }))
                        .padding(.leading, 28)
                        .accessibilityIdentifier("trackpadGestures")
                    if showsWarning, let status = manager.status { warning(status) }
                    VStack(alignment: .leading, spacing: 4) {
                        selectionRow(String(localized: "Fingers")) {
                            TrackpadChoiceButton(selection: $manager.settings.fingers,
                                entries: [.option(String(localized: "Three fingers"), 3),
                                          .option(String(localized: "Four fingers"), 4)],
                                title: manager.settings.fingers == 3 ? String(localized: "Three fingers") : String(localized: "Four fingers"),
                                label: String(localized: "Fingers"))
                        }
                        selectionRow(String(localized: "Sensitivity")) {
                            TrackpadChoiceButton(selection: Binding(
                                get: { TrackpadSensitivity.allCases.firstIndex(of: manager.settings.sensitivity) ?? 2 },
                                set: { manager.settings.sensitivity = TrackpadSensitivity.allCases[$0] }),
                                entries: TrackpadSensitivity.allCases.enumerated().map { .option($0.element.title, $0.offset) },
                                title: manager.settings.sensitivity.title, label: String(localized: "Sensitivity"))
                        }
                        VStack(spacing: 4) {
                            ForEach(directions, id: \.self) { direction in
                                selectionRow(title(direction), icon: "arrow.\(direction.rawValue)") {
                                    TrackpadChoiceButton(selection: Binding(
                                        get: { manager.settings[direction] }, set: { manager.settings[direction] = $0 }),
                                        entries: actionEntries, title: TrackpadGestureAction.title(manager.settings[direction]),
                                        label: title(direction))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .disabled(!manager.settings.enabled)
                    Text("Applies to the window under the pointer when the gesture starts.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
                .padding(.leading, 12)
            } label: {
                HStack(spacing: 8) {
                    Label("Trackpad Gestures", systemImage: "hand.draw")
                    Button(action: { showingGestureExample.toggle() }) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Trackpad gestures example")
                    .accessibilityIdentifier("trackpadGestureExample")
                    .popover(isPresented: $showingGestureExample, arrowEdge: .trailing) {
                        TrackpadGestureExampleView()
                    }
                    if showsWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Gestures paused")
                            .help(manager.status ?? "")
                    }
                }
            }
        }
    }

    private func selectionRow(_ title: String, icon: String? = nil,
                              control: () -> TrackpadChoiceButton) -> some View {
        let choice = control()
        return HStack(spacing: 8) {
            Group {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                else { Color.clear }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 12)
            choice.frame(width: choice.preferredWidth, height: 26)
        }
        .frame(minHeight: 28)
    }

    private func warning(_ status: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.system(size: 17))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Gestures paused").fontWeight(.semibold)
                Text(status).font(.caption).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if manager.systemConflict {
                        Button("Open Trackpad Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                        }
                    }
                    Button(action: manager.refreshStatus) {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 36 / 255, green: 107 / 255, blue: 104 / 255))
                        .foregroundStyle(.white)
                        .help("Check gesture availability again")
                        .accessibilityIdentifier("refreshTrackpadGestureStatus")
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func title(_ direction: TrackpadDirection) -> String {
        switch direction {
        case .up: return String(localized: "Swipe up")
        case .down: return String(localized: "Swipe down")
        case .left: return String(localized: "Swipe left")
        case .right: return String(localized: "Swipe right")
        }
    }

    private func group(for action: WindowAction) -> WindowActionCategory {
        if [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(action) { return .corners }
        switch action {
        case .topVerticalThird, .middleVerticalThird, .bottomVerticalThird,
             .topVerticalTwoThirds, .bottomVerticalTwoThirds,
             .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird: return .thirds
        case .doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight,
             .halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight,
             .specified: return .size
        default: return action.classification ?? action.category ?? .other
        }
    }

    private var actionEntries: [TrackpadChoiceEntry] {
        var entries = TrackpadGestureAction.common.map { TrackpadChoiceEntry.option(TrackpadGestureAction.title($0), $0) }
        entries += [.separator, .option(String(localized: "None"), TrackpadGestureAction.none)]
        let more = groups.compactMap { category -> TrackpadChoiceEntry? in
            let actions = TrackpadGestureAction.actions.filter {
                !TrackpadGestureAction.common.contains($0.rawValue) && group(for: $0) == category
            }
            return actions.isEmpty ? nil : .submenu(category.displayName, actions.map { .option(TrackpadGestureAction.title($0.rawValue), $0.rawValue) })
        }
        entries.append(.submenu(String(localized: "More"), more))
        return entries
    }
}

/// An illustration only: it never sends gestures or moves application windows.
private struct TrackpadGestureExampleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var windowFrame = CGRect(x: 0.23, y: 0.22, width: 0.54, height: 0.60)
    @State private var windowOpacity = 1.0
    @State private var contactOffset = CGSize.zero
    @State private var contactOpacity = 0.65

    private let contacts: [(CGFloat, CGFloat, CGFloat)] = [
        (0, 13, 11), (20, 1, 12), (41, 5, 12), (61, 23, 10)
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Swipe to arrange windows")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
            desktop
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                ZStack(alignment: .topLeading) {
                    ForEach(contacts.indices, id: \.self) { index in
                        let contact = contacts[index]
                        Circle().fill(.secondary)
                            .frame(width: contact.2, height: contact.2)
                            .offset(x: contact.0, y: contact.1)
                    }
                }
                .frame(width: 76, height: 37, alignment: .topLeading)
                .offset(contactOffset)
                .opacity(contactOpacity)
            }
            .frame(width: 156, height: 98)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
        }
        .padding(20)
        .frame(width: 440)
        // SwiftUI cancels this finite sequence when the popover is dismissed.
        .task(id: reduceMotion) { await demonstrate() }
    }

    private var desktop: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.20, green: 0.24, blue: 0.33), Color(red: 0.20, green: 0.29, blue: 0.27)]
                            : [Color(red: 0.88, green: 0.90, blue: 0.95), Color(red: 0.82, green: 0.89, blue: 0.87)],
                        startPoint: .topTrailing, endPoint: .bottomLeading))
                HStack(spacing: 4) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == 3 ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .position(x: geometry.size.width / 2, y: geometry.size.height - 12)
                exampleWindow
                    .frame(width: geometry.size.width * windowFrame.width,
                           height: geometry.size.height * windowFrame.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .opacity(windowOpacity)
                    .offset(x: geometry.size.width * windowFrame.minX,
                            y: geometry.size.height * windowFrame.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .frame(height: 225)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Four-finger gestures: swipe left or right to snap a window, up to maximize, and down to minimize.")
    }

    private var exampleWindow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle().fill(.secondary.opacity(0.45)).frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 7).frame(height: 17)
            .background(.primary.opacity(0.025))
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.035))
                        .frame(width: max(0, geometry.size.width * 0.23))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<4) { index in
                            Capsule()
                                .fill(index == 0 ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12))
                                .frame(width: max(0, geometry.size.width * (index == 0 ? 0.32 : 0.52)), height: 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(9)
        }
        .clipped()
    }

    @MainActor private func demonstrate() async {
        windowFrame = CGRect(x: 0.23, y: 0.22, width: 0.54, height: 0.60)
        windowOpacity = 1
        contactOffset = .zero
        contactOpacity = 0.65
        guard !reduceMotion else { return }
        let steps: [(CGRect, CGSize)] = [
            (CGRect(x: 0.02, y: 0.08, width: 0.47, height: 0.81), CGSize(width: -22, height: 0)),
            (CGRect(x: 0.51, y: 0.08, width: 0.47, height: 0.81), CGSize(width: 22, height: 0)),
            (CGRect(x: 0.02, y: 0.08, width: 0.96, height: 0.81), CGSize(width: 0, height: -17)),
            (CGRect(x: 0.56, y: 0.92, width: 0.02, height: 0.02), CGSize(width: 0, height: 17))
        ]
        do {
            try await Task.sleep(for: .milliseconds(250))
            for (index, step) in steps.enumerated() {
                contactOffset = .zero
                contactOpacity = 0
                withAnimation(.easeOut(duration: 0.25)) { contactOpacity = 0.9 }
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.70)) {
                    contactOffset = step.1
                }
                try await Task.sleep(for: .milliseconds(187))
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.725)) {
                    windowFrame = step.0
                    windowOpacity = index == 3 ? 0 : 1
                }
                try await Task.sleep(for: .milliseconds(513))
                withAnimation(.easeOut(duration: 0.30)) { contactOpacity = 0 }
                try await Task.sleep(for: .milliseconds(1050))
            }
            contactOffset = .zero
            withAnimation(.easeOut(duration: 0.20)) { contactOpacity = 0.65 }
        } catch is CancellationError {
            // Dismissal or a Reduce Motion change stops pending steps immediately.
        } catch { }
    }
}

private enum TrackpadChoiceEntry {
    case option(String, Int)
    case separator
    case submenu(String, [TrackpadChoiceEntry])
}

// Scope shortcut suppression to these configuration choices, leaving application menus alone.
private final class TrackpadChoiceMenuItem: NSMenuItem {
    override class var usesUserKeyEquivalents: Bool {
        get { false }
        set { }
    }
    override var keyEquivalent: String {
        get { "" }
        set { }
    }
    override var userKeyEquivalent: String { "" }
    override var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        get { [] }
        set { }
    }
}

private struct TrackpadChoiceButton: NSViewRepresentable {
    @Binding var selection: Int
    let entries: [TrackpadChoiceEntry]
    let title: String
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    var preferredWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return min(260, ceil((title as NSString).size(withAttributes: [.font: font]).width) + 44)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .rounded
        button.alignment = .right
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.altersStateOfSelectedItem = false
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let menu = NSMenu()
        menu.autoenablesItems = false
        let heading = TrackpadChoiceMenuItem(title: title, action: nil, keyEquivalent: "")
        heading.isHidden = true
        menu.addItem(heading)
        populate(menu, entries: entries, coordinator: context.coordinator)
        button.menu = menu
        button.selectItem(at: 0)
        button.isEnabled = isEnabled
        button.toolTip = title
        button.setAccessibilityLabel(label)
    }

    private func populate(_ menu: NSMenu, entries: [TrackpadChoiceEntry], coordinator: Coordinator) {
        for entry in entries {
            switch entry {
            case .separator: menu.addItem(.separator())
            case let .option(title, value):
                let item = TrackpadChoiceMenuItem(title: title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
                item.target = coordinator
                item.tag = value
                item.state = value == selection ? .on : .off
                menu.addItem(item)
            case let .submenu(title, children):
                let item = TrackpadChoiceMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                populate(submenu, entries: children, coordinator: coordinator)
                item.submenu = submenu
                menu.addItem(item)
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: TrackpadChoiceButton
        init(_ parent: TrackpadChoiceButton) { self.parent = parent }
        @objc func choose(_ item: NSMenuItem) { parent.selection = item.tag }
    }
}
