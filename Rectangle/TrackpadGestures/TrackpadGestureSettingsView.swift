import SwiftUI

struct TrackpadGestureSettingsView: View {
    @Bindable private var manager = TrackpadGestureManager.shared
    private let directions: [TrackpadDirection] = [.up, .down, .left, .right]
    private let groups: [WindowActionCategory] = [.halves, .corners, .thirds, .fourths, .sixths, .eighths,
        .ninths, .twelfths, .sixteenths, .size, .display, .move, .other]
    private var showsWarning: Bool { manager.settings.enabled && manager.status != nil }
    private var choiceWidth: CGFloat {
        let titles = directions.map { TrackpadGestureAction.title(manager.settings[$0]) }
            + [String(localized: "Three fingers"), String(localized: "Four fingers"), manager.settings.sensitivity.title]
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let longest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(260, max(170, ceil(longest) + 44))
    }

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

    private func selectionRow<Control: View>(_ title: String, icon: String? = nil,
                                             @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                else { Color.clear }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 12)
            control().frame(width: choiceWidth, height: 26)
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
