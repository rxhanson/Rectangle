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

enum ToggleAction: Int {
    case disableForAllApps = 0,
        disableForCurrentApp = 1
    
    var notficationName: Notification.Name {
        return Notification.Name(name)
    }
    
    func post() {
        NotificationCenter.default.post(name: notficationName, object: nil)
    }
    
    var name: String {
        switch self {
        case .disableForAllApps: return "disableForAllApps"
        case .disableForCurrentApp: return "disableForCurrentApp"
        }
    }
    
    var defaultShortcut: Shortcut? {
        switch self {
        case .disableForAllApps: return Shortcut( 0, kVK_F12 )
        case .disableForCurrentApp: return Shortcut( cmd, kVK_F12 )
        }
    }
}

enum WindowAction: Int {
    case leftHalf = 0,
    rightHalf = 1,
    maximize = 2,
    maximizeHeight = 3,
    previousDisplay = 4,
    nextDisplay = 5,
    larger = 8,
    smaller = 9,
    bottomHalf = 10,
    topHalf = 11,
    center = 12,
    bottomLeft = 13,
    bottomRight = 14,
    topLeft = 15,
    topRight = 16,
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
                         topLeft, topRight, bottomLeft, bottomRight,
                         firstThird, firstTwoThirds, centerThird, lastTwoThirds, lastThird,
                         maximize, almostMaximize, maximizeHeight, smaller, larger, center, restore,
                         nextDisplay, previousDisplay,
                         moveLeft, moveRight, moveUp, moveDown]
    
    func post() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self))
    }
    
    func postSnap(screen: NSScreen) {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, updateRestoreRect: false, screen: screen))
    }
    
    // Determines where separators should be used in the menu
    var firstInGroup: Bool {
        switch self {
        case .leftHalf, .topLeft, .firstThird, .maximize, .nextDisplay, .moveLeft:
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
        case .larger: return "larger"
        case .smaller: return "smaller"
        case .bottomHalf: return "bottomHalf"
        case .topHalf: return "topHalf"
        case .center: return "center"
        case .bottomLeft: return "bottomLeft"
        case .bottomRight: return "bottomRight"
        case .topLeft: return "topLeft"
        case .topRight: return "topRight"
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
        var value: String
        
        switch self {
        case .leftHalf:
            key = "Xc8-Sm-pig.title"
            value = "Left Half"
        case .rightHalf:
            key = "F8S-GI-LiB.title"
            value = "Right Half"
        case .maximize:
            key = "8oe-J2-oUU.title"
            value = "Maximize"
        case .maximizeHeight:
            key = "6DV-cd-fda.title"
            value = "Maximize Height"
        case .previousDisplay:
            key = "QwF-QN-YH7.title"
            value = "Previous Display"
        case .nextDisplay:
            key = "Jnd-Lc-nlh.title"
            value = "Next Display"
        case .larger:
            key = "Eah-KL-kbn.title"
            value = "Larger"
        case .smaller:
            key = "MzN-CJ-ASD.title"
            value = "Smaller"
        case .bottomHalf:
            key = "ec4-FB-fMa.title"
            value = "Bottom Half"
        case .topHalf:
            key = "d7y-s8-7GE.title"
            value = "Top Half"
        case .center:
            key = "8Bg-SZ-hDO.title"
            value = "Center"
        case .bottomLeft:
            key = "6ma-hP-5xX.title"
            value = "Bottom Left"
        case .bottomRight:
            key = "J6t-sg-Wwz.title"
            value = "Bottom Right"
        case .topLeft:
            key = "adp-cN-qkh.title"
            value = "Top Left"
        case .topRight:
            key = "0Ak-33-SM7.title"
            value = "Top Right"
        case .restore:
            key = "C9v-g0-DH8.title"
            value = "Restore"
        case .firstThird:
            key = "F12-EV-Lfz.title"
            value = "First Third"
        case .firstTwoThirds:
            key = "3zd-xE-oWl.title"
            value = "First Two Thirds"
        case .centerThird:
            key = "7YK-9Z-lzw.title"
            value = "Center Third"
        case .lastTwoThirds:
            key = "08q-Ce-1QL.title"
            value = "Last Two Thirds"
        case .lastThird:
            key = "cRm-wn-Yv6.title"
            value = "Last Third"
        case .moveLeft:
            key = "v2f-bX-xiM.title"
            value = "Move Left"
        case .moveRight:
            key = "rzr-Qq-702.title"
            value = "Move Right"
        case .moveUp:
            key = "HOm-BV-2jc.title"
            value = "Move Up"
        case .moveDown:
            key = "1Rc-Od-eP5.title"
            value = "Move Down"
        case .almostMaximize:
            key = "e57-QJ-6bL.title"
            value = "Almost Maximize"
        }
        
        return NSLocalizedString(key, tableName: "Main", value: value, comment: "")
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
    
    var resizes: Bool {
        switch self {
        case .moveUp, .moveDown, .moveLeft, .moveRight, .center, .nextDisplay, .previousDisplay: return false
        default: return true
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
        case .larger: return Shortcut( ctrl|alt|shift, kVK_RightArrow )
        case .smaller: return Shortcut( ctrl|alt|shift, kVK_LeftArrow )
        case .bottomHalf: return Shortcut( cmd|alt, kVK_DownArrow )
        case .topHalf: return Shortcut( cmd|alt, kVK_UpArrow )
        case .center: return Shortcut( alt|cmd, kVK_ANSI_C )
        case .bottomLeft: return Shortcut( cmd|ctrl|shift, kVK_LeftArrow )
        case .bottomRight: return Shortcut( cmd|ctrl|shift, kVK_RightArrow )
        case .topLeft: return Shortcut( ctrl|cmd, kVK_LeftArrow )
        case .topRight: return Shortcut( ctrl|cmd, kVK_RightArrow )
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
        case .bottomLeft: return Shortcut( ctrl|alt, kVK_ANSI_J )
        case .bottomRight: return Shortcut( ctrl|alt, kVK_ANSI_K )
        case .topLeft: return Shortcut( ctrl|alt, kVK_ANSI_U )
        case .topRight: return Shortcut( ctrl|alt, kVK_ANSI_I )
        case .maximize: return Shortcut( ctrl|alt, kVK_Return )
        case .maximizeHeight: return Shortcut( ctrl|alt|shift, kVK_UpArrow )
        case .previousDisplay: return Shortcut( ctrl|alt|cmd, kVK_LeftArrow )
        case .nextDisplay: return Shortcut( ctrl|alt|cmd, kVK_RightArrow )
        case .larger: return Shortcut( ctrl|alt, kVK_ANSI_Equal )
        case .smaller: return Shortcut( ctrl|alt, kVK_ANSI_Minus )
        case .center: return Shortcut( ctrl|alt, kVK_ANSI_C )
        case .restore: return Shortcut( ctrl|alt, kVK_Delete)
        case .firstThird: return Shortcut( ctrl|alt, kVK_ANSI_D )
        case .firstTwoThirds: return Shortcut( ctrl|alt, kVK_ANSI_E )
        case .centerThird: return Shortcut( ctrl|alt, kVK_ANSI_F )
        case .lastTwoThirds: return Shortcut( ctrl|alt, kVK_ANSI_T )
        case .lastThird: return Shortcut( ctrl|alt, kVK_ANSI_G )
        default: return nil
        }
    }
    
    var image: NSImage {
        switch self {
        case .leftHalf: return NSImage(imageLiteralResourceName: "leftHalfTemplate")
        case .rightHalf: return NSImage(imageLiteralResourceName: "rightHalfTemplate")
        case .maximize: return NSImage(imageLiteralResourceName: "maximizeTemplate")
        case .maximizeHeight: return NSImage(imageLiteralResourceName: "maximizeHeightTemplate")
        case .previousDisplay: return NSImage(imageLiteralResourceName: "prevDisplayTemplate")
        case .nextDisplay: return NSImage(imageLiteralResourceName: "nextDisplayTemplate")
        case .larger: return NSImage(imageLiteralResourceName: "makeLargerTemplate")
        case .smaller: return NSImage(imageLiteralResourceName: "makeSmallerTemplate")
        case .bottomHalf: return NSImage(imageLiteralResourceName: "bottomHalfTemplate")
        case .topHalf: return NSImage(imageLiteralResourceName: "topHalfTemplate")
        case .center: return NSImage(imageLiteralResourceName: "centerTemplate")
        case .bottomLeft: return NSImage(imageLiteralResourceName: "bottomLeftTemplate")
        case .bottomRight: return NSImage(imageLiteralResourceName: "bottomRightTemplate")
        case .topLeft: return NSImage(imageLiteralResourceName: "topLeftTemplate")
        case .topRight: return NSImage(imageLiteralResourceName: "topRightTemplate")
        case .restore: return NSImage(imageLiteralResourceName: "restoreTemplate")
        case .firstThird: return NSImage(imageLiteralResourceName: "firstThirdTemplate")
        case .firstTwoThirds: return NSImage(imageLiteralResourceName: "firstTwoThirdsTemplate")
        case .centerThird: return NSImage(imageLiteralResourceName: "centerThirdTemplate")
        case .lastTwoThirds: return NSImage(imageLiteralResourceName: "lastTwoThirdsTemplate")
        case .lastThird: return NSImage(imageLiteralResourceName: "lastThirdTemplate")
        case .moveLeft: return NSImage(imageLiteralResourceName: "moveLeftTemplate")
        case .moveRight: return NSImage(imageLiteralResourceName: "moveRightTemplate")
        case .moveUp: return NSImage(imageLiteralResourceName: "moveUpTemplate")
        case .moveDown: return NSImage(imageLiteralResourceName: "moveDownTemplate")
        case .almostMaximize: return NSImage(imageLiteralResourceName: "almostMaximizeTemplate")
        }
    }
    
    var gapSharedEdge: Edge {
        switch self {
        case .leftHalf: return .right
        case .rightHalf: return .left
        case .bottomHalf: return .top
        case .topHalf: return .bottom
        case .bottomLeft: return [.top, .right]
        case .bottomRight: return [.top, .left]
        case .topLeft: return [.bottom, .right]
        case .topRight: return [.bottom, .left]
        default:
            return .none
        }
    }
    
    var gapsApplicable: Bool {
        switch self {
        case .leftHalf, .rightHalf, .bottomHalf, .topHalf, .maximize, .bottomLeft, .bottomRight, .topLeft, .topRight, .firstThird, .firstTwoThirds, .centerThird, .lastTwoThirds, .lastThird:
            return true
        default:
            return false
        }
    }
}

enum SubWindowAction {
    case leftThird,
    centerVerticalThird,
    rightThird,
    leftTwoThirds,
    rightTwoThirds,
    
    topThird,
    centerHorizontalThird,
    bottomThird,
    topTwoThirds,
    bottomTwoThirds
    
    var gapSharedEdge: Edge {
        switch self {
        case .leftThird: return .right
        case .centerVerticalThird: return [.right, .left]
        case .rightThird: return .left
        case .leftTwoThirds: return .right
        case .rightTwoThirds: return .left
        case .topThird: return .bottom
        case .centerHorizontalThird: return [.top, .bottom]
        case .bottomThird: return .top
        case .topTwoThirds: return .bottom
        case .bottomTwoThirds: return .top
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
