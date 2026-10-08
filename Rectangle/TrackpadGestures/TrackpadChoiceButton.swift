import SwiftUI

struct TrackpadChoiceButton: NSViewRepresentable {
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

enum TrackpadChoiceEntry {
    case option(String, Int)
    case separator
    case submenu(String, [TrackpadChoiceEntry])
}

// Scope shortcut suppression to these configuration choices, leaving application menus alone.
final class TrackpadChoiceMenuItem: NSMenuItem {
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
