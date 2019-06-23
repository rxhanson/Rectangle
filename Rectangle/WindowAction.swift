//
//  WindowAction.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import Carbon
import Cocoa

fileprivate let alt = NSEvent.ModifierFlags.option.rawValue
fileprivate let ctrl = NSEvent.ModifierFlags.control.rawValue
fileprivate let shift = NSEvent.ModifierFlags.shift.rawValue
fileprivate let cmd = NSEvent.ModifierFlags.command.rawValue

enum WindowAction: Int {
    case leftHalf = 0, rightHalf = 1, maximize = 2, maximizeHeight = 3, previousDisplay = 4, nextDisplay = 5, undo = 6, redo = 7, larger = 8, smaller = 9, bottomHalf = 10, topHalf = 11, center = 12, lowerLeft = 13, lowerRight = 14, upperLeft = 15, upperRight = 16, nextThird = 17, previousThird = 18
    
    static let active = [leftHalf, rightHalf, maximize, maximizeHeight, previousDisplay, nextDisplay, undo, redo, larger, smaller, bottomHalf, topHalf, center, lowerLeft, lowerRight, upperLeft, upperRight]
    
    func post() {
        NotificationCenter.default.post(name: notificationName, object: self)
    }
    
    var name: String {
        switch self {
        case .leftHalf: return "leftHalf"
        case .rightHalf: return "rightHalf"
        case .maximize: return "maximize"
        case .maximizeHeight: return "maximizeHeight"
        case .previousDisplay: return "previousDisplay"
        case .nextDisplay: return "nextDisplay"
        case .undo: return "undo"
        case .redo: return "redo"
        case .larger: return "larger"
        case .smaller: return "smaller"
        case .bottomHalf: return "bottomHalf"
        case .topHalf: return "topHalf"
        case .center: return "center"
        case .lowerLeft: return "lowerLeft"
        case .lowerRight: return "lowerRight"
        case .upperLeft: return "upperLeft"
        case .upperRight: return "upperRight"
        case .nextThird: return "nextThird"
        case .previousThird: return "previousThird"
        }
    }
    
    var notificationName: Notification.Name {
        return Notification.Name(name)
    }
    
    var isMoveToDisplay: Bool {
        switch self {
        case .previousDisplay, .nextDisplay: return true
        default: return false
        }
    }
    
    var spectacleDefault: Shortcut {
        switch self {
        case .leftHalf: return Shortcut( cmd|alt, kVK_LeftArrow )
        case .rightHalf: return Shortcut( cmd|alt, kVK_RightArrow )
        case .maximize: return Shortcut( cmd|alt, kVK_ANSI_F )
        case .maximizeHeight: return Shortcut( ctrl|alt|shift, kVK_UpArrow )
        case .previousDisplay: return Shortcut( ctrl|alt|cmd, kVK_LeftArrow )
        case .nextDisplay:  return Shortcut( ctrl|alt|cmd, kVK_RightArrow )
        case .undo: return Shortcut( cmd|alt, kVK_ANSI_Z )
        case .redo: return Shortcut( cmd|alt|shift, kVK_ANSI_Z )
        case .larger: return Shortcut( ctrl|alt|shift, kVK_RightArrow )
        case .smaller: return Shortcut( ctrl|alt|shift, kVK_LeftArrow )
        case .bottomHalf: return Shortcut( cmd|alt, kVK_DownArrow )
        case .topHalf: return Shortcut( cmd|alt, kVK_UpArrow )
        case .center: return Shortcut( alt|cmd, kVK_ANSI_C )
        case .lowerLeft: return Shortcut( cmd|ctrl|shift, kVK_LeftArrow )
        case .lowerRight: return Shortcut( cmd|ctrl|shift, kVK_RightArrow )
        case .upperLeft: return Shortcut( ctrl|cmd, kVK_LeftArrow )
        case .upperRight: return Shortcut( ctrl|cmd, kVK_RightArrow )
        case .nextThird: return Shortcut( ctrl|alt, kVK_RightArrow )
        case .previousThird: return Shortcut( ctrl|alt, kVK_LeftArrow )
        }
    }
    
    var alternateDefault: Shortcut {
        switch self {
        case .leftHalf: return Shortcut( ctrl|alt, kVK_LeftArrow )
        case .rightHalf: return Shortcut( ctrl|alt, kVK_RightArrow )
        case .bottomHalf: return Shortcut( ctrl|alt, kVK_DownArrow )
        case .topHalf: return Shortcut( ctrl|alt, kVK_UpArrow )
        case .lowerLeft: return Shortcut( ctrl|alt, kVK_ANSI_J )
        case .lowerRight: return Shortcut( ctrl|alt, kVK_ANSI_K )
        case .upperLeft: return Shortcut( ctrl|alt, kVK_ANSI_U )
        case .upperRight: return Shortcut( ctrl|alt, kVK_ANSI_I )
        case .maximize: return Shortcut( ctrl|alt, kVK_Return )
        case .maximizeHeight: return Shortcut( ctrl|alt|shift, kVK_UpArrow )
        case .previousDisplay: return Shortcut( ctrl|alt|cmd, kVK_LeftArrow )
        case .nextDisplay: return Shortcut( ctrl|alt|cmd, kVK_RightArrow )
        case .undo: return Shortcut( ctrl|alt, kVK_Delete )
        case .redo: return Shortcut( ctrl|alt|shift, kVK_Delete )
        case .larger: return Shortcut( ctrl|alt, kVK_ANSI_Equal )
        case .smaller: return Shortcut( ctrl|alt, kVK_ANSI_Minus )
        case .center: return Shortcut( ctrl|alt, kVK_ANSI_C )
        case .nextThird: return Shortcut( ctrl|alt, kVK_ANSI_F )
        case .previousThird: return Shortcut( ctrl|alt, kVK_ANSI_D )
        }
    }
}

struct Shortcut {
    let keyCode: Int
    let modifierFlags: UInt
    
    init(_ modifierFlags: UInt, _ keyCode: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
    
    var dict: [String: UInt] {
        return ["keyCode": UInt(keyCode), "modifierFlags": modifierFlags]
    }
}
