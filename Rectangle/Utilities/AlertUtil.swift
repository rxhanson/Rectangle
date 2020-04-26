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
    
}
