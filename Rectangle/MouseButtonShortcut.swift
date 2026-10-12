/// MouseButtonShortcut.swift

import Cocoa
import MASShortcut

/// A window action shortcut on a mouse button rather than a key. It is stored
/// like a keyboard shortcut, as a key code and modifier flags, using key codes
/// no key produces. So it takes the action's one shortcut slot, cycles with
/// duplicates the way keys do, and goes through config export and import
/// unchanged.
final class MouseButtonShortcut: MASShortcut {

    /// Event button numbers, from 2 for the middle button. Left and right
    /// clicks can't be shortcuts.
    static let buttonNumbers = 2...31

    /// Real key codes stay below 0xC0. Keeping both these codes and their low
    /// byte clear of them means a version of Rectangle from before mouse
    /// buttons, finding one in a config, sees a key that can never be pressed.
    private static let keyCodeBase = 0xFFC0

    var buttonNumber: Int { keyCode - Self.keyCodeBase }

    convenience init(buttonNumber: Int, modifierFlags: NSEvent.ModifierFlags) {
        self.init(keyCode: Self.keyCodeBase + buttonNumber, modifierFlags: modifierFlags)
    }

    /// The shortcut for a mouse down event, if its button can be one.
    convenience init?(buttonPress event: NSEvent) {
        guard Self.buttonNumbers.contains(event.buttonNumber) else { return nil }
        self.init(buttonNumber: event.buttonNumber, modifierFlags: event.modifierFlags)
    }

    static func buttonNumber(forKeyCode keyCode: Int) -> Int? {
        let buttonNumber = keyCode - keyCodeBase
        return buttonNumbers.contains(buttonNumber) ? buttonNumber : nil
    }

    static func isMouseButton(_ shortcut: MASShortcut) -> Bool {
        buttonNumber(forKeyCode: shortcut.keyCode) != nil
    }

    /// Shortcuts read back from user defaults are plain MASShortcuts, which
    /// can't name a mouse button.
    static func displayable(_ shortcut: MASShortcut) -> MASShortcut {
        guard !(shortcut is MouseButtonShortcut),
              let buttonNumber = buttonNumber(forKeyCode: shortcut.keyCode)
        else {
            return shortcut
        }
        return MouseButtonShortcut(buttonNumber: buttonNumber, modifierFlags: shortcut.modifierFlags)
    }

    /// Kept short to fit a shortcut recorder along with modifiers. Buttons are
    /// numbered from 1 for the left one, as System Settings does, so the side
    /// buttons are 4 and 5.
    override var keyCodeString: String? {
        buttonNumber == 2
            ? String(localized: "Middle Button", comment: "The middle mouse button in a shortcut")
            : String(localized: "Button \(buttonNumber + 1)",
                     comment: "A numbered mouse button in a shortcut. The side buttons on most mice are 4 and 5.")
    }

    /// A menu item can't show a mouse button as its key equivalent.
    override var keyCodeStringForKeyEquivalent: String? { "" }

    override var description: String {
        let buttonName = keyCodeString ?? ""
        return modifierFlagsString.isEmpty ? buttonName : modifierFlagsString + " " + buttonName
    }
}

/// Decides what becomes of each mouse button event while shortcuts are bound.
/// A press that triggers a shortcut has its drags and release swallowed along
/// with it, so the app underneath never gets half a click, even when the
/// modifiers or the bindings change before the button comes back up.
struct MouseButtonShortcutRouter {

    enum Decision: Equatable {
        case passThrough
        case swallow
        case trigger(ShortcutCycle.ShortcutIdentity)
    }

    private(set) var heldButtons = Set<Int>()

    mutating func route(_ type: NSEvent.EventType, buttonNumber: Int, modifierFlags: NSEvent.ModifierFlags,
                        isBound: (ShortcutCycle.ShortcutIdentity) -> Bool) -> Decision {
        switch type {
        case .otherMouseDown:
            // A button pressed while still held lost its release somewhere.
            heldButtons.remove(buttonNumber)
            guard MouseButtonShortcut.buttonNumbers.contains(buttonNumber) else { return .passThrough }
            let identity = ShortcutCycle.ShortcutIdentity(MouseButtonShortcut(buttonNumber: buttonNumber, modifierFlags: modifierFlags))
            guard isBound(identity) else { return .passThrough }
            heldButtons.insert(buttonNumber)
            return .trigger(identity)
        case .otherMouseDragged:
            return heldButtons.contains(buttonNumber) ? .swallow : .passThrough
        case .otherMouseUp:
            return heldButtons.remove(buttonNumber) != nil ? .swallow : .passThrough
        default:
            return .passThrough
        }
    }
}

/// Where a mouse button shortcut was pressed, for working on the window under
/// the pointer.
struct MouseButtonPress {
    let location: CGPoint
    let windowId: CGWindowID?
}

protocol MouseButtonBindingStore {
    func bindShortcut(_ shortcut: MASShortcut, toAction action: @escaping (MouseButtonPress) -> Void)
    func breakAllBindings()
}

/// Runs the bound mouse button shortcuts from an event tap. The tap only
/// exists while a shortcut is bound, or while a press it swallowed is still
/// held, so that the release is swallowed too.
final class MouseButtonShortcutMonitor: MouseButtonBindingStore {

    typealias EventMonitorFactory = (_ filterer: @escaping (NSEvent) -> Bool) -> EventMonitor

    // Bindings change on the main thread while the tap's thread routes events.
    private let lock = NSLock()
    private var router = MouseButtonShortcutRouter()
    private var actions = [ShortcutCycle.ShortcutIdentity: (MouseButtonPress) -> Void]()
    private var bindingGeneration = 0
    private let makeEventMonitor: EventMonitorFactory
    private lazy var eventMonitor: EventMonitor = makeEventMonitor { [weak self] event in
        self?.filter(event) ?? false
    }

    init(makeEventMonitor: @escaping EventMonitorFactory = { filterer in
        ActiveEventMonitor(mask: [.otherMouseDown, .otherMouseDragged, .otherMouseUp], filterer: filterer, handler: { _ in })
    }) {
        self.makeEventMonitor = makeEventMonitor
    }

    func bindShortcut(_ shortcut: MASShortcut, toAction action: @escaping (MouseButtonPress) -> Void) {
        lock.lock()
        actions[ShortcutCycle.ShortcutIdentity(shortcut)] = action
        lock.unlock()
        updateListening()
    }

    func breakAllBindings() {
        lock.lock()
        actions.removeAll()
        bindingGeneration += 1
        lock.unlock()
        updateListening()
    }

    private func updateListening() {
        lock.lock()
        let isNeeded = !actions.isEmpty || !router.heldButtons.isEmpty
        lock.unlock()
        if isNeeded {
            if !eventMonitor.running {
                eventMonitor.start()
            }
        } else {
            eventMonitor.stop()
        }
    }

    private func isBindingGeneration(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == bindingGeneration
    }

    /// Runs on the event tap's thread. Returning true swallows the event.
    private func filter(_ event: NSEvent) -> Bool {
        lock.lock()
        let decision = router.route(event.type, buttonNumber: event.buttonNumber, modifierFlags: event.modifierFlags) {
            actions[$0] != nil
        }
        var action: ((MouseButtonPress) -> Void)?
        if case .trigger(let identity) = decision {
            action = actions[identity]
        }
        let generation = bindingGeneration
        let isIdle = actions.isEmpty && router.heldButtons.isEmpty
        lock.unlock()

        if let action, let cgEvent = event.cgEvent {
            let windowId = cgEvent.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
            let press = MouseButtonPress(location: cgEvent.location, windowId: windowId > 0 ? CGWindowID(exactly: windowId) : nil)
            DispatchQueue.main.async { [weak self] in
                // Shortcuts that stood down after the press, when recording
                // starts say, don't run it.
                guard self?.isBindingGeneration(generation) == true else { return }
                action(press)
            }
        }
        if isIdle {
            DispatchQueue.main.async { [weak self] in self?.updateListening() }
        }
        return decision != .passThrough
    }
}
