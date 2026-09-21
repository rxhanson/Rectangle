import SwiftUI
import MASShortcut

struct MASShortcutViewRepresentable: NSViewRepresentable {
    let defaultsKey: String
    let validator: MASShortcutValidator?

    func makeNSView(context: Context) -> MASShortcutView {
        let view = MASShortcutView()
        view.setAssociatedUserDefaultsKey(defaultsKey, withTransformerName: MASDictionaryTransformerName)
        if let validator = validator {
            view.shortcutValidator = validator
        }
        return view
    }

    func updateNSView(_ nsView: MASShortcutView, context: Context) {
        if let validator = validator {
            nsView.shortcutValidator = validator
        }
    }
}
