import SwiftUI

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
