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
import MASShortcut

fileprivate let alt = NSEvent.ModifierFlags.option.rawValue
fileprivate let ctrl = NSEvent.ModifierFlags.control.rawValue
fileprivate let shift = NSEvent.ModifierFlags.shift.rawValue
fileprivate let cmd = NSEvent.ModifierFlags.command.rawValue

enum WindowAction: Int, Codable {
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
    almostMaximize = 29,
    centerHalf = 30,
    firstFourth = 31,
    secondFourth = 32,
    thirdFourth = 33,
    lastFourth = 34,
    firstThreeFourths = 35,
    lastThreeFourths = 36,
    topLeftSixth = 37,
    topCenterSixth = 38,
    topRightSixth = 39,
    bottomLeftSixth = 40,
    bottomCenterSixth = 41,
    bottomRightSixth = 42,
    specified = 43,
    reverseAll = 44,
    topLeftNinth = 45,
    topCenterNinth = 46,
    topRightNinth = 47,
    middleLeftNinth = 48,
    middleCenterNinth = 49,
    middleRightNinth = 50,
    bottomLeftNinth = 51,
    bottomCenterNinth = 52,
    bottomRightNinth = 53,
    topLeftThird = 54,
    topRightThird = 55,
    bottomLeftThird = 56,
    bottomRightThird = 57,
    topLeftEighth = 58,
    topCenterLeftEighth = 59,
    topCenterRightEighth = 60,
    topRightEighth = 61,
    bottomLeftEighth = 62,
    bottomCenterLeftEighth = 63,
    bottomCenterRightEighth = 64,
    bottomRightEighth = 65,
    tileAll = 66,
    cascadeAll = 67

    // Order matters here - it's used in the menu
    static let active = [leftHalf, rightHalf, centerHalf, topHalf, bottomHalf,
                         topLeft, topRight, bottomLeft, bottomRight,
                         firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds,
                         maximize, almostMaximize, maximizeHeight, smaller, larger, center, restore,
                         nextDisplay, previousDisplay,
                         moveLeft, moveRight, moveUp, moveDown,
                         firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, lastThreeFourths,
                         topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth,
                         specified, reverseAll,
                         topLeftNinth, topCenterNinth, topRightNinth,
                         middleLeftNinth, middleCenterNinth, middleRightNinth,
                         bottomLeftNinth, bottomCenterNinth, bottomRightNinth,
                         topLeftThird, topRightThird, bottomLeftThird, bottomRightThird,
                         topLeftEighth, topCenterLeftEighth, topCenterRightEighth, topRightEighth,
                         bottomLeftEighth, bottomCenterLeftEighth, bottomCenterRightEighth, bottomRightEighth,
                         tileAll, cascadeAll
    ]

    func post() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self))
    }
    
    func postMenu() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, source: .menuItem))
    }

    func postSnap(windowElement: AccessibilityElement?, windowId: CGWindowID?, screen: NSScreen) {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, updateRestoreRect: false, screen: screen, windowElement: windowElement, windowId: windowId, source: .dragToSnap))
    }
    
    func postUrl() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, source: .url))
    }

    // Determines where separators should be used in the menu
    var firstInGroup: Bool {
        switch self {
        case .leftHalf, .topLeft, .firstThird, .maximize, .nextDisplay, .moveLeft, .firstFourth, .topLeftSixth:
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
        case .centerHalf: return "centerHalf"
        case .firstFourth: return "firstFourth"
        case .secondFourth: return "secondFourth"
        case .thirdFourth: return "thirdFourth"
        case .lastFourth: return "lastFourth"
        case .firstThreeFourths: return "firstThreeFourths"
        case .lastThreeFourths: return "lastThreeFourths"
        case .topLeftSixth: return "topLeftSixth"
        case .topCenterSixth: return "topCenterSixth"
        case .topRightSixth: return "topRightSixth"
        case .bottomLeftSixth: return "bottomLeftSixth"
        case .bottomCenterSixth: return "bottomCenterSixth"
        case .bottomRightSixth: return "bottomRightSixth"
        case .specified: return "specified"
        case .reverseAll: return "reverseAll"
        case .topLeftNinth: return "topLeftNinth"
        case .topCenterNinth: return "topCenterNinth"
        case .topRightNinth: return "topRightNinth"
        case .middleLeftNinth: return "middleLeftNinth"
        case .middleCenterNinth: return "middleCenterNinth"
        case .middleRightNinth: return "middleRightNinth"
        case .bottomLeftNinth: return "bottomLeftNinth"
        case .bottomCenterNinth: return "bottomCenterNinth"
        case .bottomRightNinth: return "bottomRightNinth"
        case .topLeftThird: return "topLeftThird"
        case .topRightThird: return "topRightThird"
        case .bottomLeftThird: return "bottomLeftThird"
        case .bottomRightThird: return "bottomRightThird"
        case .topLeftEighth: return "topLeftEighth"
        case .topCenterLeftEighth: return "topCenterLeftEighth"
        case .topCenterRightEighth: return "topCenterRightEighth"
        case .topRightEighth: return "topRightEighth"
        case .bottomLeftEighth: return "bottomLeftEighth"
        case .bottomCenterLeftEighth: return "bottomCenterLeftEighth"
        case .bottomCenterRightEighth: return "bottomCenterRightEighth"
        case .bottomRightEighth: return "bottomRightEighth"
        case .tileAll: return "tileAll"
        case .cascadeAll: return "cascadeAll"
        }
    }

    var displayName: String? {
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
        case .centerHalf:
            key = "bRX-dV-iAR.title"
            value = "Center Half"
        case .firstFourth:
            key = "Q6Q-6J-okH.title"
            value = "First Fourth"
        case .secondFourth:
            key = "Fko-xs-gN5.title"
            value = "Second Fourth"
        case .thirdFourth:
            key = "ZTK-rS-b17.title"
            value = "Third Fourth"
        case .lastFourth:
            key = "6HX-rn-VIp.title"
            value = "Last Fourth"
        case .firstThreeFourths:
            key = "T9Z-QF-gwc.title"
            value = "First Three Fourths"
        case .lastThreeFourths:
            key = "nwX-h6-fwm.title"
            value = "Last Three Fourths"
        case .topLeftSixth:
            key = "mFt-Kg-UYG.title"
            value = "Top Left Sixth"
        case .topCenterSixth:
            key = "TTx-7X-Wie.title"
            value = "Top Center Sixth"
        case .topRightSixth:
            key = "f3Q-q7-Pcy.title"
            value = "Top Right Sixth"
        case .bottomLeftSixth:
            key = "LqQ-pM-jRN.title"
            value = "Bottom Left Sixth"
        case .bottomCenterSixth:
            key = "iOQ-1e-esP.title"
            value = "Bottom Center Sixth"
        case .bottomRightSixth:
            key = "m2F-eA-g7w.title"
            value = "Bottom Right Sixth"
        case .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth:
            return nil
        case .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird:
            return nil
        case .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth,
                .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth:
            return nil
        case .specified, .reverseAll, .tileAll, .cascadeAll:
            return nil
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
        case .center, .nextDisplay, .previousDisplay: return false
        case .moveUp, .moveDown, .moveLeft, .moveRight: return Defaults.resizeOnDirectionalMove.enabled
        default: return true
        }
    }
    
    var isDragSnappable: Bool {
        switch self {
        case .restore, .previousDisplay, .nextDisplay, .moveUp, .moveDown, .moveLeft, .moveRight, .specified, .reverseAll, .tileAll, .cascadeAll, .smaller, .larger,
            // Ninths
            .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth,
            // Corner thirds
            .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird,
            // Eighths
            .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth, .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth:
            return false
        default:
            return true
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
        case .centerHalf: return NSImage(imageLiteralResourceName: "halfWidthCenterTemplate")
        case .firstFourth: return NSImage(imageLiteralResourceName: "leftFourthTemplate")
        case .secondFourth: return NSImage(imageLiteralResourceName: "centerLeftFourthTemplate")
        case .thirdFourth: return NSImage(imageLiteralResourceName: "centerRightFourthTemplate")
        case .lastFourth: return NSImage(imageLiteralResourceName: "rightFourthTemplate")
        case .firstThreeFourths: return NSImage(imageLiteralResourceName: "firstThreeFourthsTemplate")
        case .lastThreeFourths: return NSImage(imageLiteralResourceName: "lastThreeFourthsTemplate")
        case .topLeftSixth: return NSImage(imageLiteralResourceName: "topLeftSixthTemplate")
        case .topCenterSixth: return NSImage(imageLiteralResourceName: "topCenterSixthTemplate")
        case .topRightSixth: return NSImage(imageLiteralResourceName: "topRightSixthTemplate")
        case .bottomLeftSixth: return NSImage(imageLiteralResourceName: "bottomLeftSixthTemplate")
        case .bottomCenterSixth: return NSImage(imageLiteralResourceName: "bottomCenterSixthTemplate")
        case .bottomRightSixth: return NSImage(imageLiteralResourceName: "bottomRightSixthTemplate")
        case .topLeftNinth: return NSImage()
        case .topCenterNinth: return NSImage()
        case .topRightNinth: return NSImage()
        case .middleLeftNinth: return NSImage()
        case .middleCenterNinth: return NSImage()
        case .middleRightNinth: return NSImage()
        case .bottomLeftNinth: return NSImage()
        case .bottomCenterNinth: return NSImage()
        case .bottomRightNinth: return NSImage()
        case .topLeftThird: return NSImage()
        case .topRightThird: return NSImage()
        case .bottomLeftThird: return NSImage()
        case .bottomRightThird: return NSImage()
        case .topLeftEighth: return  NSImage()
        case .topCenterLeftEighth: return  NSImage()
        case .topCenterRightEighth: return  NSImage()
        case .topRightEighth: return  NSImage()
        case .bottomLeftEighth: return  NSImage()
        case .bottomCenterLeftEighth: return  NSImage()
        case .bottomCenterRightEighth: return  NSImage()
        case .bottomRightEighth: return  NSImage()
        case .specified, .reverseAll: return NSImage()
        case .tileAll: return NSImage()
        case .cascadeAll: return NSImage()
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
        case .moveUp: return Defaults.resizeOnDirectionalMove.enabled ? .bottom : .none
        case .moveDown: return Defaults.resizeOnDirectionalMove.enabled ? .top : .none
        case .moveLeft: return Defaults.resizeOnDirectionalMove.enabled ? .right : .none
        case .moveRight: return Defaults.resizeOnDirectionalMove.enabled ? .left : .none
        default:
            return .none
        }
    }

    var gapsApplicable: Dimension {
        switch self {
        case .leftHalf, .rightHalf, .bottomHalf, .topHalf, .centerHalf, .bottomLeft, .bottomRight, .topLeft, .topRight, .firstThird, .firstTwoThirds, .centerThird, .lastTwoThirds, .lastThird,
             .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths, .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
            .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth,
            .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird,
            .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth,
            .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth:
            return .both
        case .moveUp, .moveDown:
            return Defaults.resizeOnDirectionalMove.enabled ? .vertical : .none;
        case .moveLeft, .moveRight:
            return Defaults.resizeOnDirectionalMove.enabled ? .horizontal : .none;
        case .maximize:
            return Defaults.applyGapsToMaximize.userDisabled ? .none : .both;
        case .maximizeHeight:
            return Defaults.applyGapsToMaximizeHeight.userDisabled ? .none : .vertical;
        case .almostMaximize, .previousDisplay, .nextDisplay, .larger, .smaller, .center, .restore, .specified, .reverseAll, .tileAll, .cascadeAll:
            return .none
        }
    }
    
    var category: WindowActionCategory? { // used to specify a submenu
        switch self {
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths: return .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: return .sixths
        case .moveUp, .moveDown, .moveLeft, .moveRight: return .move
        default: return nil
        }
    }
    
    var classification: WindowActionCategory? {
        switch self {
        case .firstThird, .firstTwoThirds, .centerThird, .lastTwoThirds, .lastThird: return .thirds
        default: return nil
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
    bottomTwoThirds,
    
    leftFourth,
    centerLeftFourth,
    centerRightFourth,
    rightFourth,
    
    topFourth,
    centerTopFourth,
    centerBottomFourth,
    bottomFourth,
    
    rightThreeFourths,
    bottomThreeFourths,
    leftThreeFourths,
    topThreeFourths,
    
    centerVerticalHalf,
    centerHorizontalHalf,
    
    topLeftSixthLandscape,
    topCenterSixthLandscape,
    topRightSixthLandscape,
    bottomLeftSixthLandscape,
    bottomCenterSixthLandscape,
    bottomRightSixthLandscape,
    
    topLeftSixthPortrait,
    topRightSixthPortrait,
    leftCenterSixthPortrait,
    rightCenterSixthPortrait,
    bottomLeftSixthPortrait,
    bottomRightSixthPortrait,
    
    topLeftTwoSixthsLandscape,
    topLeftTwoSixthsPortrait,
    topRightTwoSixthsLandscape,
    topRightTwoSixthsPortrait,
    
    bottomLeftTwoSixthsLandscape,
    bottomLeftTwoSixthsPortrait,
    bottomRightTwoSixthsLandscape,
    bottomRightTwoSixthsPortrait,
    
    topLeftNinth,
    topCenterNinth,
    topRightNinth,
    middleLeftNinth,
    middleCenterNinth,
    middleRightNinth,
    bottomLeftNinth,
    bottomCenterNinth,
    bottomRightNinth,
         
    topLeftThird,
    topRightThird,
    bottomLeftThird,
    bottomRightThird,
         
    topLeftEighth,
    topCenterLeftEighth,
    topCenterRightEighth,
    topRightEighth,
    bottomLeftEighth,
    bottomCenterLeftEighth,
    bottomCenterRightEighth,
    bottomRightEighth,
        
    maximize

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
        case .leftFourth: return .right
        case .centerLeftFourth: return [.right, .left]
        case .centerRightFourth: return [.right, .left]
        case .rightFourth: return .left
        case .topFourth: return .bottom
        case .centerTopFourth: return [.top, .bottom]
        case .centerBottomFourth: return [.top, .bottom]
        case .bottomFourth: return .top
        case .rightThreeFourths: return .left
        case .bottomThreeFourths: return .top
        case .leftThreeFourths: return .right
        case .topThreeFourths: return .bottom
        case .centerVerticalHalf: return [.right, .left]
        case .centerHorizontalHalf: return [.top, .bottom]
        case .topLeftSixthLandscape: return [.right, .bottom]
        case .topCenterSixthLandscape: return [.right, .left, .bottom]
        case .topRightSixthLandscape: return [.left, .bottom]
        case .bottomLeftSixthLandscape: return [.top, .right]
        case .bottomCenterSixthLandscape: return [.left, .right, .top]
        case .bottomRightSixthLandscape: return [.left, .top]
        case .topLeftSixthPortrait: return [.right, .bottom]
        case .topRightSixthPortrait: return [.left, .bottom]
        case .leftCenterSixthPortrait: return [.top, .bottom, .right]
        case .rightCenterSixthPortrait: return [.left, .top, .bottom]
        case .bottomLeftSixthPortrait: return [.top, .right]
        case .bottomRightSixthPortrait: return [.left, .top]
        case .topLeftTwoSixthsLandscape: return [.right, .bottom]
        case .topLeftTwoSixthsPortrait: return [.right, .bottom]
        case .topRightTwoSixthsLandscape: return [.left, .bottom]
        case .topRightTwoSixthsPortrait: return [.left, .bottom]
        case .bottomLeftTwoSixthsLandscape: return [.right, .top]
        case .bottomLeftTwoSixthsPortrait: return [.right, .top]
        case .bottomRightTwoSixthsLandscape: return [.left, .top]
        case .bottomRightTwoSixthsPortrait: return [.left, .top]
        case .topLeftNinth: return [.right, .bottom]
        case .topCenterNinth: return [.right, .left, .bottom]
        case .topRightNinth: return [.left, .bottom]
        case .middleLeftNinth: return [.top, .right, .bottom]
        case .middleCenterNinth: return [.top, .right, .bottom, .left]
        case .middleRightNinth: return [.left, .top, .bottom]
        case .bottomLeftNinth: return [.top, .right]
        case .bottomCenterNinth: return [.left, .top, .right]
        case .bottomRightNinth: return [.left, .top]
        case .topLeftThird: return [.right, .bottom]
        case .topRightThird: return [.left, .bottom]
        case .bottomLeftThird: return [.right, .top]
        case .bottomRightThird: return [.left, .top]
        case .topLeftEighth: return  [.right, .bottom]
        case .topCenterLeftEighth: return  [.right, .left, .bottom]
        case .topCenterRightEighth: return  [.right, .left, .bottom]
        case .topRightEighth: return  [.left, .bottom]
        case .bottomLeftEighth: return  [.right, .top]
        case .bottomCenterLeftEighth: return  [.right, .left, .top]
        case .bottomCenterRightEighth: return  [.right, .left, .top]
        case .bottomRightEighth: return  [.left, .top]
        case .maximize: return .none
        }
    }
}

struct Shortcut: Codable {
    let keyCode: Int
    let modifierFlags: UInt
    
    init(_ modifierFlags: UInt, _ keyCode: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
    
    init(masShortcut: MASShortcut) {
        self.keyCode = masShortcut.keyCode
        self.modifierFlags = masShortcut.modifierFlags.rawValue
    }
    
    func toMASSHortcut() -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags))
    }
    
    func displayString() -> String {
        let masShortcut = toMASSHortcut()
        return masShortcut.modifierFlagsString + masShortcut.keyCodeString
    }
}
