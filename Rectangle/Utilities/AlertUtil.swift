/// AlertUtil.swift

import Cocoa

class AlertUtil {

    static func oneButtonAlert(question: String, text: String, confirmText: String = "OK") {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmText)
        alert.runModal()
    }
    
    static func twoButtonAlert(question: String, text: String, confirmText: String = "OK", cancelText: String = "Cancel") -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmText)
        alert.addButton(withTitle: cancelText)
        return alert.runModal()
    }
    
    static func threeButtonAlert(question: String, text: String, buttonOneText: String, buttonTwoText: String, buttonThreeText: String) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: buttonOneText)
        alert.addButton(withTitle: buttonTwoText)
        alert.addButton(withTitle: buttonThreeText)
        return alert.runModal()
    }

    static func textInputAlert(question: String,
                               text: String,
                               defaultValue: String,
                               confirmText: String = "OK",
                               cancelText: String = "Cancel") -> String? {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirmText)
        alert.addButton(withTitle: cancelText)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
