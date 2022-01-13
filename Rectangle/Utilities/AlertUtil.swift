//
//  AlertUtil.swift
//  Rectangle
//
//  Created by Ryan Hanson on 4/26/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

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
}
