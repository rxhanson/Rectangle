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
    case leftHalf = 0,
    rightHalf = 1,
    maximize = 2,
    maximizeHeight = 3,
    previousDisplay = 4,
    nextDisplay = 5,
    undo = 6,
    redo = 7,
    larger = 8,
    smaller = 9,
    bottomHalf = 10,
    topHalf = 11,
    center = 12,
    lowerLeft = 13,
    lowerRight = 14,
    upperLeft = 15,
    upperRight = 16,
    nextThird = 17,
    previousThird = 18,
    restore = 19,
    firstThird = 20,
    firstTwoThirds = 21,
    centerThird = 22,
    lastTwoThirds = 23,
    lastThird = 24,
    moveLeft = 25,
    moveRight = 26,
    moveUp = 27,
    moveDown = 28,
    almostMaximize = 29
    
    // Order matters here - it's used in the menu
    static let active = [leftHalf, rightHalf, topHalf, bottomHalf,
                         upperRight, upperLeft, lowerLeft, lowerRight,
                         firstThird, firstTwoThirds, centerThird, lastTwoThirds, lastThird,
                         maximize, almostMaximize, maximizeHeight, smaller, larger, center, restore,
                         nextDisplay, previousDisplay,
                         moveLeft, moveRight, moveUp, moveDown]
    
    func post() {
        NotificationCenter.default.post(name: notificationName, object: self)
    }
    
    // Determines where separators should be used in the menu
    var firstInGroup: Bool {
        switch self {
        case .leftHalf, .upperRight, .firstThird, .maximize, .nextDisplay, .moveLeft:
            return true
        default:
            return false
        }
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
        case .restore: return "restore"
        case .firstThird: return "firstThird"
        case .firstTwoThirds: return "firstTwoThirds"
        case .centerThird: return "centerThird"
        case .lastTwoThirds: return "lastTwoThirds"
        case .lastThird: return "lastThird"
        case .moveLeft: return "moveLeft"
        case .moveRight: return "moveRight"
        case .moveUp: return "moveUp"
        case .moveDown: return "moveDown"
        case .almostMaximize: return "almostMaximize"
        }
    }

    var displayName: String {
        var key: String
        
        switch self {
        case .leftHalf: key = "Left Half"
        case .rightHalf: key = "Right Half"
        case .maximize: key = "Maximize"
        case .maximizeHeight: key = "Maximize Height"
        case .previousDisplay: key = "Previous Display"
        case .nextDisplay: key = "Next Display"
        case .undo: key = "Undo"
        case .redo: key = "Redo"
        case .larger: key = "Larger"
        case .smaller: key = "Smaller"
        case .bottomHalf: key = "Bottom Half"
        case .topHalf: key = "Top Half"
        case .center: key = "Center"
        case .lowerLeft: key = "Lower Left"
        case .lowerRight: key = "Lower Right"
        case .upperLeft: key = "Upper Left"
        case .upperRight: key = "Upper Right"
        case .nextThird: key = "Next Third"
        case .previousThird: key = "Previous Third"
        case .restore: key = "Restore"
        case .firstThird: key = "First Third"
        case .firstTwoThirds: key = "First Two Thirds"
        case .centerThird: key = "Center Third"
        case .lastTwoThirds: key = "Last Two Thirds"
        case .lastThird: key = "Last Third"
        case .moveLeft: key = "Move Left"
        case .moveRight: key = "Move Right"
        case .moveUp: key = "Move Up"
        case .moveDown: key = "Move Down"
        case .almostMaximize: key = "Almost Maximize"
        }
        
        return NSLocalizedString(key, comment: key)
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
    
    var spectacleDefault: Shortcut? {
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
        case .restore: return Shortcut( ctrl|alt, kVK_Delete)
        default: return nil
        }
    }
    
    var alternateDefault: Shortcut? {
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
        case .undo: return Shortcut( cmd|alt, kVK_Delete )
        case .redo: return Shortcut( cmd|alt|shift, kVK_Delete )
        case .larger: return Shortcut( ctrl|alt, kVK_ANSI_Equal )
        case .smaller: return Shortcut( ctrl|alt, kVK_ANSI_Minus )
        case .center: return Shortcut( ctrl|alt, kVK_ANSI_C )
        case .nextThird: return Shortcut( ctrl|alt, kVK_ANSI_F )
        case .previousThird: return Shortcut( ctrl|alt, kVK_ANSI_D )
        case .restore: return Shortcut( ctrl|alt, kVK_Delete)
        case .firstThird: return Shortcut( ctrl|alt, kVK_ANSI_D )
        case .firstTwoThirds: return Shortcut( ctrl|alt, kVK_ANSI_E )
        case .centerThird: return Shortcut( ctrl|alt, kVK_ANSI_F )
        case .lastTwoThirds: return Shortcut( ctrl|alt, kVK_ANSI_T )
        case .lastThird: return Shortcut( ctrl|alt, kVK_ANSI_G )
        default: return nil
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
