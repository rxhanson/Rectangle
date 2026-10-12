/// WindowActionShortcutView.swift

import Cocoa
import MASShortcut

/// A recorder for a window action's shortcut, which can also be a mouse
/// button: pressing the middle button or an extra button while recording,
/// with any modifiers held, records it in place of a key.
final class WindowActionShortcutView: MASShortcutView {

    private var mouseButtonMonitor: Any?

    // Dynamic, so that setting these from Swift still notifies key-value
    // observers, such as the ShortcutRecordingObserver watching recording.
    override dynamic var shortcutValue: MASShortcut? {
        get { super.shortcutValue }
        set { super.shortcutValue = newValue.map(MouseButtonShortcut.displayable) }
    }

    override dynamic var isRecording: Bool {
        didSet { updateMouseButtonMonitor() }
    }

    deinit {
        if let mouseButtonMonitor {
            NSEvent.removeMonitor(mouseButtonMonitor)
        }
    }

    /// Records the button of a mouse down event, if recording and the button
    /// can be a shortcut. Returns whether it was recorded.
    ///
    /// Only presses in the recorder's own window count, and none while a
    /// modal runs: MASShortcutView keeps recording behind its alert for a
    /// shortcut that's already taken, and turns its key monitoring back on
    /// when the alert closes whether or not it's still recording.
    @discardableResult
    func recordMouseButton(_ event: NSEvent) -> Bool {
        guard isRecording,
              event.window === window,
              NSApp.modalWindow == nil,
              let shortcut = MouseButtonShortcut(buttonPress: event)
        else { return false }
        shortcutValue = shortcut
        isRecording = false
        return true
    }

    private func updateMouseButtonMonitor() {
        if isRecording {
            guard mouseButtonMonitor == nil else { return }
            mouseButtonMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                self?.recordMouseButton(event) == true ? nil : event
            }
        } else if let mouseButtonMonitor {
            NSEvent.removeMonitor(mouseButtonMonitor)
            self.mouseButtonMonitor = nil
        }
    }
}
