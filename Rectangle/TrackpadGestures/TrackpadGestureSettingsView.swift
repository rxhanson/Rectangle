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
