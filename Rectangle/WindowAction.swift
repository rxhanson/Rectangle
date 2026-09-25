/// WindowAction.swift

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
         cascadeAll = 67,
         leftTodo = 68,
         rightTodo = 69,
         cascadeActiveApp = 70,
         centerProminently = 71,
         doubleHeightUp = 72,
         doubleHeightDown = 73,
         doubleWidthLeft = 74,
         doubleWidthRight = 75,
         halveHeightUp = 76,
         halveHeightDown = 77,
         halveWidthLeft = 78,
         halveWidthRight = 79,
         largerWidth = 80,
         smallerWidth = 81,
         largerHeight = 82,
         smallerHeight = 83,
         centerTwoThirds = 84,
         centerThreeFourths = 85,
         tileActiveApp = 86,
         topVerticalThird = 87,
         middleVerticalThird = 88,
         bottomVerticalThird = 89,
         topVerticalTwoThirds = 90,
         bottomVerticalTwoThirds = 91,
         topLeftTwelfth = 92,
         topCenterLeftTwelfth = 93,
         topCenterRightTwelfth = 94,
         topRightTwelfth = 95,
         middleLeftTwelfth = 96,
         middleCenterLeftTwelfth = 97,
         middleCenterRightTwelfth = 98,
         middleRightTwelfth = 99,
         bottomLeftTwelfth = 100,
         bottomCenterLeftTwelfth = 101,
         bottomCenterRightTwelfth = 102,
         bottomRightTwelfth = 103,
         topLeftSixteenth = 104,
         topCenterLeftSixteenth = 105,
         topCenterRightSixteenth = 106,
         topRightSixteenth = 107,
         upperMiddleLeftSixteenth = 108,
         upperMiddleCenterLeftSixteenth = 109,
         upperMiddleCenterRightSixteenth = 110,
         upperMiddleRightSixteenth = 111,
         lowerMiddleLeftSixteenth = 112,
         lowerMiddleCenterLeftSixteenth = 113,
         lowerMiddleCenterRightSixteenth = 114,
         lowerMiddleRightSixteenth = 115,
         bottomLeftSixteenth = 116,
         bottomCenterLeftSixteenth = 117,
         bottomCenterRightSixteenth = 118,
         bottomRightSixteenth = 119,
         displayOne = 120,
         displayTwo = 121,
         displayThree = 122,
         displayFour = 123,
         displayFive = 124,
         displaySix = 125,
         displaySeven = 126,
         displayEight = 127,
         displayNine = 128,
         tileRows = 129,
         tileColumns = 130

    // Order matters here - it's used in the menu
    static let active = [leftHalf, rightHalf, centerHalf, topHalf, bottomHalf,
                         topLeft, topRight, bottomLeft, bottomRight,
                         firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds,
                         topVerticalThird, middleVerticalThird, bottomVerticalThird, topVerticalTwoThirds, bottomVerticalTwoThirds,
                         maximize, almostMaximize, maximizeHeight, larger, smaller, largerWidth, smallerWidth, largerHeight, smallerHeight,
                         center, centerProminently, restore,
                         nextDisplay, previousDisplay,
                         moveLeft, moveRight, moveUp, moveDown,
                         firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, centerThreeFourths, lastThreeFourths,
                         topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth,
                         specified, reverseAll,
                         topLeftThird, topRightThird, bottomLeftThird, bottomRightThird,
                         topLeftEighth, topCenterLeftEighth, topCenterRightEighth, topRightEighth,
                         bottomLeftEighth, bottomCenterLeftEighth, bottomCenterRightEighth, bottomRightEighth,
                         topLeftNinth, topCenterNinth, topRightNinth,
                         middleLeftNinth, middleCenterNinth, middleRightNinth,
                         bottomLeftNinth, bottomCenterNinth, bottomRightNinth,
                         topLeftTwelfth, topCenterLeftTwelfth, topCenterRightTwelfth, topRightTwelfth,
                         middleLeftTwelfth, middleCenterLeftTwelfth, middleCenterRightTwelfth, middleRightTwelfth,
                         bottomLeftTwelfth, bottomCenterLeftTwelfth, bottomCenterRightTwelfth, bottomRightTwelfth,
                         topLeftSixteenth, topCenterLeftSixteenth, topCenterRightSixteenth, topRightSixteenth,
                         upperMiddleLeftSixteenth, upperMiddleCenterLeftSixteenth, upperMiddleCenterRightSixteenth, upperMiddleRightSixteenth,
                         lowerMiddleLeftSixteenth, lowerMiddleCenterLeftSixteenth, lowerMiddleCenterRightSixteenth, lowerMiddleRightSixteenth,
                         bottomLeftSixteenth, bottomCenterLeftSixteenth, bottomCenterRightSixteenth, bottomRightSixteenth,
                         doubleHeightUp, doubleHeightDown, doubleWidthLeft, doubleWidthRight,
                         halveHeightUp, halveHeightDown, halveWidthLeft, halveWidthRight,
                         tileAll, tileRows, tileColumns, cascadeAll,
                         leftTodo, rightTodo,
                         cascadeActiveApp, tileActiveApp,
                         displayOne, displayTwo, displayThree, displayFour, displayFive,
                         displaySix, displaySeven, displayEight, displayNine
    ]

    func post() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self))
    }
    
    func postMenu() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, source: .menuItem))
    }

    func postSnap(windowElement: AccessibilityElement?, windowId: CGWindowID?, screen: NSScreen,
                  completion: (() -> Void)? = nil) {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, updateRestoreRect: false, screen: screen, windowElement: windowElement, windowId: windowId, source: .dragToSnap, completion: completion))
    }
    
    func postUrl() {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, source: .url))
    }
    
    func postTitleBar(windowElement: AccessibilityElement?, screen: NSScreen? = nil) {
        NotificationCenter.default.post(name: notificationName, object: ExecutionParameters(self, screen: screen, windowElement: windowElement, source: .titleBar))
    }

    // Determines where separators should be used in the menu
    var firstInGroup: Bool {
        switch self {
        case .leftHalf, .topLeft, .firstThird, .maximize, .almostMaximize, .nextDisplay, .moveLeft, .firstFourth, .topLeftSixth, .topLeftEighth, .topLeftNinth, .topLeftTwelfth, .topLeftSixteenth, .tileRows:
            return true
        default:
            return false
        }
    }
    
    var excludedFromMenu: Bool {
        switch self {
        case .smallerWidth, .largerWidth, .topVerticalThird, .middleVerticalThird, .bottomVerticalThird, .topVerticalTwoThirds, .bottomVerticalTwoThirds: return true
        default: return false
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
        case .centerTwoThirds: return "centerTwoThirds"
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
        case .centerThreeFourths: return "centerThreeFourths"
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
        case .doubleHeightUp: return "doubleHeightUp"
        case .doubleHeightDown: return "doubleHeightDown"
        case .doubleWidthLeft: return "doubleWidthLeft"
        case .doubleWidthRight: return "doubleWidthRight"
        case .halveHeightUp: return "halveHeightUp"
        case .halveHeightDown: return "halveHeightDown"
        case .halveWidthLeft: return "halveWidthLeft"
        case .halveWidthRight: return "halveWidthRight"
        case .tileAll: return "tileAll"
        case .tileRows: return "tileRows"
        case .tileColumns: return "tileColumns"
        case .cascadeAll: return "cascadeAll"
        case .leftTodo: return "leftTodo"
        case .rightTodo: return "rightTodo"
        case .cascadeActiveApp: return "cascadeActiveApp"
        case .tileActiveApp: return "tileActiveApp"
        case .centerProminently: return "centerProminently"
        case .largerWidth: return "largerWidth"
        case .smallerWidth: return "smallerWidth"
        case .largerHeight: return "largerHeight"
        case .smallerHeight: return "smallerHeight"
        case .topVerticalThird: return "topVerticalThird"
        case .middleVerticalThird: return "middleVerticalThird"
        case .bottomVerticalThird: return "bottomVerticalThird"
        case .topVerticalTwoThirds: return "topVerticalTwoThirds"
        case .bottomVerticalTwoThirds: return "bottomVerticalTwoThirds"
        case .topLeftTwelfth: return "topLeftTwelfth"
        case .topCenterLeftTwelfth: return "topCenterLeftTwelfth"
        case .topCenterRightTwelfth: return "topCenterRightTwelfth"
        case .topRightTwelfth: return "topRightTwelfth"
        case .middleLeftTwelfth: return "middleLeftTwelfth"
        case .middleCenterLeftTwelfth: return "middleCenterLeftTwelfth"
        case .middleCenterRightTwelfth: return "middleCenterRightTwelfth"
        case .middleRightTwelfth: return "middleRightTwelfth"
        case .bottomLeftTwelfth: return "bottomLeftTwelfth"
        case .bottomCenterLeftTwelfth: return "bottomCenterLeftTwelfth"
        case .bottomCenterRightTwelfth: return "bottomCenterRightTwelfth"
        case .bottomRightTwelfth: return "bottomRightTwelfth"
        case .topLeftSixteenth: return "topLeftSixteenth"
        case .topCenterLeftSixteenth: return "topCenterLeftSixteenth"
        case .topCenterRightSixteenth: return "topCenterRightSixteenth"
        case .topRightSixteenth: return "topRightSixteenth"
        case .upperMiddleLeftSixteenth: return "upperMiddleLeftSixteenth"
        case .upperMiddleCenterLeftSixteenth: return "upperMiddleCenterLeftSixteenth"
        case .upperMiddleCenterRightSixteenth: return "upperMiddleCenterRightSixteenth"
        case .upperMiddleRightSixteenth: return "upperMiddleRightSixteenth"
        case .lowerMiddleLeftSixteenth: return "lowerMiddleLeftSixteenth"
        case .lowerMiddleCenterLeftSixteenth: return "lowerMiddleCenterLeftSixteenth"
        case .lowerMiddleCenterRightSixteenth: return "lowerMiddleCenterRightSixteenth"
        case .lowerMiddleRightSixteenth: return "lowerMiddleRightSixteenth"
        case .bottomLeftSixteenth: return "bottomLeftSixteenth"
        case .bottomCenterLeftSixteenth: return "bottomCenterLeftSixteenth"
        case .bottomCenterRightSixteenth: return "bottomCenterRightSixteenth"
        case .bottomRightSixteenth: return "bottomRightSixteenth"
        case .displayOne: return "displayOne"
        case .displayTwo: return "displayTwo"
        case .displayThree: return "displayThree"
        case .displayFour: return "displayFour"
        case .displayFive: return "displayFive"
        case .displaySix: return "displaySix"
        case .displaySeven: return "displaySeven"
        case .displayEight: return "displayEight"
        case .displayNine: return "displayNine"
        }
    }

    var aliasName: String? {
        switch self {
        case .leftHalf: return "leftSide"
        case .rightHalf: return "rightSide"
        case .bottomHalf: return "bottomSide"
        case .topHalf: return "topSide"
        case .centerHalf: return "centerSection"
        default: return nil
        }
    }

    var displayIndex: Int? {
        switch self {
        case .displayOne: return 0
        case .displayTwo: return 1
        case .displayThree: return 2
        case .displayFour: return 3
        case .displayFive: return 4
        case .displaySix: return 5
        case .displaySeven: return 6
        case .displayEight: return 7
        case .displayNine: return 8
        default: return nil
        }
    }

    var displayName: String? {
        switch self {
        case .leftHalf:
            String(localized: "Left")
        case .rightHalf:
            String(localized: "Right")
        case .maximize:
            String(localized: "Maximize")
        case .maximizeHeight:
            String(localized: "Maximize Height")
        case .previousDisplay:
            String(localized: "Previous Display")
        case .nextDisplay:
            String(localized: "Next Display")
        case .larger:
            String(localized: "Make Larger")
        case .smaller:
            String(localized: "Make Smaller")
        case .bottomHalf:
            String(localized: "Bottom")
        case .topHalf:
            String(localized: "Top")
        case .center:
            String(localized: "Move to Center")
        case .bottomLeft:
            String(localized: "Bottom Left")
        case .bottomRight:
            String(localized: "Bottom Right")
        case .topLeft:
            String(localized: "Top Left")
        case .topRight:
            String(localized: "Top Right")
        case .restore:
            String(localized: "Restore")
        case .firstThird:
            String(localized: "First Third")
        case .firstTwoThirds:
            String(localized: "First Two Thirds")
        case .centerThird:
            String(localized: "Center Third")
        case .centerTwoThirds:
            String(localized: "Center Two Thirds")
        case .lastTwoThirds:
            String(localized: "Last Two Thirds")
        case .lastThird:
            String(localized: "Last Third")
        case .moveLeft:
            String(localized: "Move Left")
        case .moveRight:
            String(localized: "Move Right")
        case .moveUp:
            String(localized: "Move Up")
        case .moveDown:
            String(localized: "Move Down")
        case .almostMaximize:
            String(localized: "Almost Maximize")
        case .centerHalf:
            String(localized: "Center")
        case .firstFourth:
            String(localized: "First Fourth")
        case .secondFourth:
            String(localized: "Second Fourth")
        case .thirdFourth:
            String(localized: "Third Fourth")
        case .lastFourth:
            String(localized: "Last Fourth")
        case .firstThreeFourths:
            String(localized: "First Three Fourths")
        case .centerThreeFourths:
            String(localized: "Center Three Fourths")
        case .lastThreeFourths:
            String(localized: "Last Three Fourths")
        case .topLeftSixth:
            String(localized: "Top Left Sixth")
        case .topCenterSixth:
            String(localized: "Top Center Sixth")
        case .topRightSixth:
            String(localized: "Top Right Sixth")
        case .bottomLeftSixth:
            String(localized: "Bottom Left Sixth")
        case .bottomCenterSixth:
            String(localized: "Bottom Center Sixth")
        case .bottomRightSixth:
            String(localized: "Bottom Right Sixth")
        case .topLeftNinth:
            String(localized: "Top Left Ninth")
        case .topCenterNinth:
            String(localized: "Top Center Ninth")
        case .topRightNinth:
            String(localized: "Top Right Ninth")
        case .middleLeftNinth:
            String(localized: "Middle Left Ninth")
        case .middleCenterNinth:
            String(localized: "Middle Center Ninth")
        case .middleRightNinth:
            String(localized: "Middle Right Ninth")
        case .bottomLeftNinth:
            String(localized: "Bottom Left Ninth")
        case .bottomCenterNinth:
            String(localized: "Bottom Center Ninth")
        case .bottomRightNinth:
            String(localized: "Bottom Right Ninth")
        case .topLeftEighth:
            String(localized: "Top Left 8th")
        case .topCenterLeftEighth:
            String(localized: "Top Center Left 8th")
        case .topCenterRightEighth:
            String(localized: "Top Center Right 8th")
        case .topRightEighth:
            String(localized: "Top Right 8th")
        case .bottomLeftEighth:
            String(localized: "Bottom Left 8th")
        case .bottomCenterLeftEighth:
            String(localized: "Bottom Center Left 8th")
        case .bottomCenterRightEighth:
            String(localized: "Bottom Center Right 8th")
        case .bottomRightEighth:
            String(localized: "Bottom Right 8th")
        case .tileRows:
            String(localized: "Tile in Rows")
        case .tileColumns:
            String(localized: "Tile in Columns")
        case .largerWidth:
            String(localized: "Larger Width")
        case .smallerWidth:
            String(localized: "Smaller Width")
        case .topVerticalThird:
            String(localized: "Top Third")
        case .middleVerticalThird:
            String(localized: "Middle Third")
        case .bottomVerticalThird:
            String(localized: "Bottom Third")
        case .topVerticalTwoThirds:
            String(localized: "Top Two Thirds")
        case .bottomVerticalTwoThirds:
            String(localized: "Bottom Two Thirds")
        case .topLeftTwelfth:
            String(localized: "Top Left Twelfth")
        case .topCenterLeftTwelfth:
            String(localized: "Top Center Left Twelfth")
        case .topCenterRightTwelfth:
            String(localized: "Top Center Right Twelfth")
        case .topRightTwelfth:
            String(localized: "Top Right Twelfth")
        case .middleLeftTwelfth:
            String(localized: "Middle Left Twelfth")
        case .middleCenterLeftTwelfth:
            String(localized: "Middle Center Left Twelfth")
        case .middleCenterRightTwelfth:
            String(localized: "Middle Center Right Twelfth")
        case .middleRightTwelfth:
            String(localized: "Middle Right Twelfth")
        case .bottomLeftTwelfth:
            String(localized: "Bottom Left Twelfth")
        case .bottomCenterLeftTwelfth:
            String(localized: "Bottom Center Left Twelfth")
        case .bottomCenterRightTwelfth:
            String(localized: "Bottom Center Right Twelfth")
        case .bottomRightTwelfth:
            String(localized: "Bottom Right Twelfth")
        case .topLeftSixteenth:
            String(localized: "Top Left Sixteenth")
        case .topCenterLeftSixteenth:
            String(localized: "Top Center Left Sixteenth")
        case .topCenterRightSixteenth:
            String(localized: "Top Center Right Sixteenth")
        case .topRightSixteenth:
            String(localized: "Top Right Sixteenth")
        case .upperMiddleLeftSixteenth:
            String(localized: "Upper Middle Left Sixteenth")
        case .upperMiddleCenterLeftSixteenth:
            String(localized: "Upper Middle Center Left Sixteenth")
        case .upperMiddleCenterRightSixteenth:
            String(localized: "Upper Middle Center Right Sixteenth")
        case .upperMiddleRightSixteenth:
            String(localized: "Upper Middle Right Sixteenth")
        case .lowerMiddleLeftSixteenth:
            String(localized: "Lower Middle Left Sixteenth")
        case .lowerMiddleCenterLeftSixteenth:
            String(localized: "Lower Middle Center Left Sixteenth")
        case .lowerMiddleCenterRightSixteenth:
            String(localized: "Lower Middle Center Right Sixteenth")
        case .lowerMiddleRightSixteenth:
            String(localized: "Lower Middle Right Sixteenth")
        case .bottomLeftSixteenth:
            String(localized: "Bottom Left Sixteenth")
        case .bottomCenterLeftSixteenth:
            String(localized: "Bottom Center Left Sixteenth")
        case .bottomCenterRightSixteenth:
            String(localized: "Bottom Center Right Sixteenth")
        case .bottomRightSixteenth:
            String(localized: "Bottom Right Sixteenth")

        case .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird,
             .doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight,
             .halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight,
             .specified, .reverseAll, .tileAll, .cascadeAll, .leftTodo, .rightTodo,
             .cascadeActiveApp, .tileActiveApp,
             .centerProminently, .largerHeight, .smallerHeight,
             .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine:
            nil
        }
    }
    
    var settingsDisplayName: String? {
        switch self {
        case .topLeftNinth:
            return "Ninths (3x3)"
        case .topLeftTwelfth:
            return "Twelfths (3x4)"
        case .topLeftSixteenth:
            return "Sixteenths (4x4)"
        default: return nil
        }
    }

    var notificationName: Notification.Name {
        return Notification.Name(name)
    }

    var resizes: Bool {
        switch self {
        case .center, .centerProminently, .nextDisplay, .previousDisplay,
             .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine: return false
        case .moveUp, .moveDown, .moveLeft, .moveRight: return Defaults.resizeOnDirectionalMove.enabled
        default: return true
        }
    }
    
    var allowedToExtendOutsideCurrentScreenArea: Bool {
        switch self {
        case .doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight:
            return true
        default:
            return false
        }
    }
    
    var isDragSnappable: Bool {
        switch self {
        case .restore, .previousDisplay, .nextDisplay, .moveUp, .moveDown, .moveLeft, .moveRight, .specified, .reverseAll, .tileAll, .tileRows, .tileColumns, .cascadeAll, .larger, .smaller, .largerWidth, .smallerWidth, .cascadeActiveApp, .tileActiveApp,
            // Ninths
            .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth,
            // Corner thirds
            .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird,
            // Specific displays
            .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
            .displaySix, .displaySeven, .displayEight, .displayNine:
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
        case .centerTwoThirds:
            if let installVersion = Defaults.installVersion.value,
               let intInstallVersion = Int(installVersion),
               intInstallVersion > 94 {
                return Shortcut( ctrl|alt, kVK_ANSI_R )
            }
            return nil
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
        case .centerTwoThirds: return NSImage(imageLiteralResourceName: "centerTwoThirdsTemplate")
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
        case .centerThreeFourths: return NSImage(imageLiteralResourceName: "centerThreeFourthsTemplate")
        case .lastThreeFourths: return NSImage(imageLiteralResourceName: "lastThreeFourthsTemplate")
        case .topLeftSixth: return NSImage(imageLiteralResourceName: "topLeftSixthTemplate")
        case .topCenterSixth: return NSImage(imageLiteralResourceName: "topCenterSixthTemplate")
        case .topRightSixth: return NSImage(imageLiteralResourceName: "topRightSixthTemplate")
        case .bottomLeftSixth: return NSImage(imageLiteralResourceName: "bottomLeftSixthTemplate")
        case .bottomCenterSixth: return NSImage(imageLiteralResourceName: "bottomCenterSixthTemplate")
        case .bottomRightSixth: return NSImage(imageLiteralResourceName: "bottomRightSixthTemplate")
        case .topLeftNinth: return NSImage(imageLiteralResourceName: "topLeftNinthTemplate")
        case .topCenterNinth: return NSImage(imageLiteralResourceName: "topCenterNinthTemplate")
        case .topRightNinth: return NSImage(imageLiteralResourceName: "topRightNinthTemplate")
        case .middleLeftNinth: return NSImage(imageLiteralResourceName: "middleLeftNinthTemplate")
        case .middleCenterNinth: return NSImage(imageLiteralResourceName: "middleCenterNinthTemplate")
        case .middleRightNinth: return NSImage(imageLiteralResourceName: "middleRightNinthTemplate")
        case .bottomLeftNinth: return NSImage(imageLiteralResourceName: "bottomLeftNinthTemplate")
        case .bottomCenterNinth: return NSImage(imageLiteralResourceName: "bottomCenterNinthTemplate")
        case .bottomRightNinth: return NSImage(imageLiteralResourceName: "bottomRightNinthTemplate")
        case .topLeftThird: return NSImage()
        case .topRightThird: return NSImage()
        case .bottomLeftThird: return NSImage()
        case .bottomRightThird: return NSImage()
        case .topLeftEighth: return NSImage(imageLiteralResourceName: "tlEighthTemplate")
        case .topCenterLeftEighth: return NSImage(imageLiteralResourceName: "ctlEighthTemplate")
        case .topCenterRightEighth: return NSImage(imageLiteralResourceName: "ctrEighthTemplate")
        case .topRightEighth: return NSImage(imageLiteralResourceName: "trEighthTemplate")
        case .bottomLeftEighth: return NSImage(imageLiteralResourceName: "blEighthTemplate")
        case .bottomCenterLeftEighth: return NSImage(imageLiteralResourceName: "cblEighthTemplate")
        case .bottomCenterRightEighth: return NSImage(imageLiteralResourceName: "cbrEighthTemplate")
        case .bottomRightEighth: return NSImage(imageLiteralResourceName: "brEighthTemplate")
        case .doubleHeightUp: return  NSImage()
        case .doubleHeightDown: return  NSImage()
        case .doubleWidthLeft: return  NSImage()
        case .doubleWidthRight: return  NSImage()
        case .halveHeightUp: return  NSImage()
        case .halveHeightDown: return  NSImage()
        case .halveWidthLeft: return  NSImage()
        case .halveWidthRight: return  NSImage()
        case .specified, .reverseAll: return NSImage()
        case .tileAll: return NSImage()
        case .tileRows: return NSImage(imageLiteralResourceName: "tileRowsTemplate")
        case .tileColumns: return NSImage(imageLiteralResourceName: "tileColumnsTemplate")
        case .cascadeAll: return NSImage()
        case .leftTodo: return NSImage()
        case .rightTodo: return NSImage()
        case .cascadeActiveApp: return NSImage()
        case .tileActiveApp: return NSImage()
        case .centerProminently: return NSImage()
        case .largerWidth: return NSImage(imageLiteralResourceName: "largerWidthTemplate")
        case .smallerWidth: return NSImage(imageLiteralResourceName: "smallerWidthTemplate")
        case .largerHeight: return NSImage()
        case .smallerHeight: return NSImage()
        case .topVerticalThird: return NSImage(imageLiteralResourceName: "topThirdTemplate")
        case .middleVerticalThird: return NSImage(imageLiteralResourceName: "centerThirdHorizontalTemplate")
        case .bottomVerticalThird: return NSImage(imageLiteralResourceName: "bottomThirdTemplate")
        case .topVerticalTwoThirds: return NSImage(imageLiteralResourceName: "topTwoThirdsTemplate")
        case .bottomVerticalTwoThirds: return NSImage(imageLiteralResourceName: "bottomTwoThirdsTemplate")
        case .topLeftTwelfth: return NSImage(imageLiteralResourceName: "topLeftTwelfthTemplate")
        case .topCenterLeftTwelfth: return NSImage(imageLiteralResourceName: "topCenterLeftTwelfthTemplate")
        case .topCenterRightTwelfth: return NSImage(imageLiteralResourceName: "topCenterRightTwelfthTemplate")
        case .topRightTwelfth: return NSImage(imageLiteralResourceName: "topRightTwelfthTemplate")
        case .middleLeftTwelfth: return NSImage(imageLiteralResourceName: "middleLeftTwelfthTemplate")
        case .middleCenterLeftTwelfth: return NSImage(imageLiteralResourceName: "middleCenterLeftTwelfthTemplate")
        case .middleCenterRightTwelfth: return NSImage(imageLiteralResourceName: "middleCenterRightTwelfthTemplate")
        case .middleRightTwelfth: return NSImage(imageLiteralResourceName: "middleRightTwelfthTemplate")
        case .bottomLeftTwelfth: return NSImage(imageLiteralResourceName: "bottomLeftTwelfthTemplate")
        case .bottomCenterLeftTwelfth: return NSImage(imageLiteralResourceName: "bottomCenterLeftTwelfthTemplate")
        case .bottomCenterRightTwelfth: return NSImage(imageLiteralResourceName: "bottomCenterRightTwelfthTemplate")
        case .bottomRightTwelfth: return NSImage(imageLiteralResourceName: "bottomRightTwelfthTemplate")
        case .topLeftSixteenth: return NSImage(imageLiteralResourceName: "topLeftSixteenthTemplate")
        case .topCenterLeftSixteenth: return NSImage(imageLiteralResourceName: "topCenterLeftSixteenthTemplate")
        case .topCenterRightSixteenth: return NSImage(imageLiteralResourceName: "topCenterRightSixteenthTemplate")
        case .topRightSixteenth: return NSImage(imageLiteralResourceName: "topRightSixteenthTemplate")
        case .upperMiddleLeftSixteenth: return NSImage(imageLiteralResourceName: "upperMiddleLeftSixteenthTemplate")
        case .upperMiddleCenterLeftSixteenth: return NSImage(imageLiteralResourceName: "upperMiddleCenterLeftSixteenthTemplate")
        case .upperMiddleCenterRightSixteenth: return NSImage(imageLiteralResourceName: "upperMiddleCenterRightSixteenthTemplate")
        case .upperMiddleRightSixteenth: return NSImage(imageLiteralResourceName: "upperMiddleRightSixteenthTemplate")
        case .lowerMiddleLeftSixteenth: return NSImage(imageLiteralResourceName: "lowerMiddleLeftSixteenthTemplate")
        case .lowerMiddleCenterLeftSixteenth: return NSImage(imageLiteralResourceName: "lowerMiddleCenterLeftSixteenthTemplate")
        case .lowerMiddleCenterRightSixteenth: return NSImage(imageLiteralResourceName: "lowerMiddleCenterRightSixteenthTemplate")
        case .lowerMiddleRightSixteenth: return NSImage(imageLiteralResourceName: "lowerMiddleRightSixteenthTemplate")
        case .bottomLeftSixteenth: return NSImage(imageLiteralResourceName: "bottomLeftSixteenthTemplate")
        case .bottomCenterLeftSixteenth: return NSImage(imageLiteralResourceName: "bottomCenterLeftSixteenthTemplate")
        case .bottomCenterRightSixteenth: return NSImage(imageLiteralResourceName: "bottomCenterRightSixteenthTemplate")
        case .bottomRightSixteenth: return NSImage(imageLiteralResourceName: "bottomRightSixteenthTemplate")
        case .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine:
            return NSImage(imageLiteralResourceName: "nextDisplayTemplate")
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
        case .leftHalf, .rightHalf, .bottomHalf, .topHalf, .centerHalf, .bottomLeft, .bottomRight, .topLeft, .topRight, .firstThird, .firstTwoThirds, .centerThird, .centerTwoThirds, .lastTwoThirds, .lastThird,
                .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths, .lastThreeFourths, .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
            .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth,
            .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird,
            .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth,
            .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth,
            .topLeftTwelfth, .topCenterLeftTwelfth, .topCenterRightTwelfth, .topRightTwelfth,
            .middleLeftTwelfth, .middleCenterLeftTwelfth, .middleCenterRightTwelfth, .middleRightTwelfth,
            .bottomLeftTwelfth, .bottomCenterLeftTwelfth, .bottomCenterRightTwelfth, .bottomRightTwelfth,
            .topLeftSixteenth, .topCenterLeftSixteenth, .topCenterRightSixteenth, .topRightSixteenth,
            .upperMiddleLeftSixteenth, .upperMiddleCenterLeftSixteenth, .upperMiddleCenterRightSixteenth, .upperMiddleRightSixteenth,
            .lowerMiddleLeftSixteenth, .lowerMiddleCenterLeftSixteenth, .lowerMiddleCenterRightSixteenth, .lowerMiddleRightSixteenth,
            .bottomLeftSixteenth, .bottomCenterLeftSixteenth, .bottomCenterRightSixteenth, .bottomRightSixteenth,
             .doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight,
             .halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight,
            .leftTodo, .rightTodo,
            .topVerticalThird, .middleVerticalThird, .bottomVerticalThird, .topVerticalTwoThirds, .bottomVerticalTwoThirds:
            return .both
        case .moveUp, .moveDown:
            return Defaults.resizeOnDirectionalMove.enabled ? .vertical : .none;
        case .moveLeft, .moveRight:
            return Defaults.resizeOnDirectionalMove.enabled ? .horizontal : .none;
        case .maximize:
            return Defaults.applyGapsToMaximize.userDisabled ? .none : .both;
        case .maximizeHeight:
            return Defaults.applyGapsToMaximizeHeight.userDisabled ? .none : .vertical;
        case .almostMaximize, .previousDisplay, .nextDisplay, .larger, .smaller, .largerWidth, .smallerWidth, .largerHeight, .smallerHeight, .center, .centerProminently, .restore, .specified, .reverseAll, .tileAll, .tileRows, .tileColumns, .cascadeAll, .cascadeActiveApp, .tileActiveApp,
             .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine:
            return .none
        }
    }

    var positionCycles: Bool {
        switch self {
        case .maximize, .almostMaximize, .maximizeHeight,
             .larger, .smaller, .largerWidth, .smallerWidth, .largerHeight, .smallerHeight,
             .center, .centerProminently,
             .restore,
             .nextDisplay, .previousDisplay,
             .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine,
             .moveLeft, .moveRight, .moveUp, .moveDown,
             .doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight,
             .halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight,
             .reverseAll, .tileAll, .tileRows, .tileColumns, .cascadeAll, .cascadeActiveApp, .tileActiveApp,
             .leftTodo, .rightTodo,
             .specified:
            return false
        default:
            return true
        }
    }

    /// Whether landing on another window in this position should be offset so
    /// the covered window stays visible. Cycling positions qualify, and so
    /// does maximize: it doesn't cycle, but two maximized windows still land
    /// exactly on top of each other.
    var overlapOffsetApplies: Bool {
        positionCycles || self == .maximize
    }

    var category: WindowActionCategory? { // used to specify a submenu
        switch self {
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: return .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths, .lastThreeFourths: return .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: return .sixths
        case .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth, .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth: return .eighths
        case .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth: return .ninths
        case .topLeftTwelfth, .topCenterLeftTwelfth, .topCenterRightTwelfth, .topRightTwelfth, .middleLeftTwelfth, .middleCenterLeftTwelfth, .middleCenterRightTwelfth, .middleRightTwelfth, .bottomLeftTwelfth, .bottomCenterLeftTwelfth, .bottomCenterRightTwelfth, .bottomRightTwelfth: return .twelfths
        case .topLeftSixteenth, .topCenterLeftSixteenth, .topCenterRightSixteenth, .topRightSixteenth, .upperMiddleLeftSixteenth, .upperMiddleCenterLeftSixteenth, .upperMiddleCenterRightSixteenth, .upperMiddleRightSixteenth, .lowerMiddleLeftSixteenth, .lowerMiddleCenterLeftSixteenth, .lowerMiddleCenterRightSixteenth, .lowerMiddleRightSixteenth, .bottomLeftSixteenth, .bottomCenterLeftSixteenth, .bottomCenterRightSixteenth, .bottomRightSixteenth: return .sixteenths
        case .tileRows, .tileColumns: return .tiling
        case .moveUp, .moveDown, .moveLeft, .moveRight: return .move
        case .almostMaximize, .maximizeHeight, .larger, .smaller, .largerWidth, .smallerWidth, .largerHeight, .smallerHeight: return .size
        default: return nil
        }
    }

    var classification: WindowActionCategory? {
        switch self {
        case .firstThird, .firstTwoThirds, .centerThird, .centerTwoThirds, .lastTwoThirds, .lastThird:
            return .thirds
        case .smaller, .larger, .smallerWidth, .largerWidth, .smallerHeight, .largerHeight:
            return .size
        case .previousDisplay, .nextDisplay,
             .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine:
            return .display
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
    centerVerticalThreeFourths,
    centerHorizontalThreeFourths,
    
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

    topLeftQuarter,
    topRightQuarter,
    bottomLeftQuarter,
    bottomRightQuarter,

    topLeftEighth,
    topCenterLeftEighth,
    topCenterRightEighth,
    topRightEighth,
    bottomLeftEighth,
    bottomCenterLeftEighth,
    bottomCenterRightEighth,
    bottomRightEighth,

    topLeftTwelfth,
    topCenterLeftTwelfth,
    topCenterRightTwelfth,
    topRightTwelfth,
    middleLeftTwelfth,
    middleCenterLeftTwelfth,
    middleCenterRightTwelfth,
    middleRightTwelfth,
    bottomLeftTwelfth,
    bottomCenterLeftTwelfth,
    bottomCenterRightTwelfth,
    bottomRightTwelfth,

    topLeftSixteenth,
    topCenterLeftSixteenth,
    topCenterRightSixteenth,
    topRightSixteenth,
    upperMiddleLeftSixteenth,
    upperMiddleCenterLeftSixteenth,
    upperMiddleCenterRightSixteenth,
    upperMiddleRightSixteenth,
    lowerMiddleLeftSixteenth,
    lowerMiddleCenterLeftSixteenth,
    lowerMiddleCenterRightSixteenth,
    lowerMiddleRightSixteenth,
    bottomLeftSixteenth,
    bottomCenterLeftSixteenth,
    bottomCenterRightSixteenth,
    bottomRightSixteenth,

    maximize,
    
    leftTodo,
    rightTodo

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
        case .centerVerticalThreeFourths: return [.right, .left]
        case .centerHorizontalThreeFourths: return [.top, .bottom]
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
        case .topLeftQuarter: return [.right, .bottom]
        case .topRightQuarter: return [.left, .bottom]
        case .bottomLeftQuarter: return [.right, .top]
        case .bottomRightQuarter: return [.left, .top]
        case .topLeftEighth: return  [.right, .bottom]
        case .topCenterLeftEighth: return  [.right, .left, .bottom]
        case .topCenterRightEighth: return  [.right, .left, .bottom]
        case .topRightEighth: return  [.left, .bottom]
        case .bottomLeftEighth: return  [.right, .top]
        case .bottomCenterLeftEighth: return  [.right, .left, .top]
        case .bottomCenterRightEighth: return  [.right, .left, .top]
        case .bottomRightEighth: return  [.left, .top]
        case .topLeftTwelfth: return [.right, .bottom]
        case .topCenterLeftTwelfth: return [.right, .left, .bottom]
        case .topCenterRightTwelfth: return [.right, .left, .bottom]
        case .topRightTwelfth: return [.left, .bottom]
        case .middleLeftTwelfth: return [.top, .right, .bottom]
        case .middleCenterLeftTwelfth: return [.top, .right, .bottom, .left]
        case .middleCenterRightTwelfth: return [.top, .right, .bottom, .left]
        case .middleRightTwelfth: return [.left, .top, .bottom]
        case .bottomLeftTwelfth: return [.top, .right]
        case .bottomCenterLeftTwelfth: return [.left, .top, .right]
        case .bottomCenterRightTwelfth: return [.left, .top, .right]
        case .bottomRightTwelfth: return [.left, .top]
        case .topLeftSixteenth: return [.right, .bottom]
        case .topCenterLeftSixteenth: return [.right, .left, .bottom]
        case .topCenterRightSixteenth: return [.right, .left, .bottom]
        case .topRightSixteenth: return [.left, .bottom]
        case .upperMiddleLeftSixteenth: return [.top, .right, .bottom]
        case .upperMiddleCenterLeftSixteenth: return [.top, .right, .bottom, .left]
        case .upperMiddleCenterRightSixteenth: return [.top, .right, .bottom, .left]
        case .upperMiddleRightSixteenth: return [.left, .top, .bottom]
        case .lowerMiddleLeftSixteenth: return [.top, .right, .bottom]
        case .lowerMiddleCenterLeftSixteenth: return [.top, .right, .bottom, .left]
        case .lowerMiddleCenterRightSixteenth: return [.top, .right, .bottom, .left]
        case .lowerMiddleRightSixteenth: return [.left, .top, .bottom]
        case .bottomLeftSixteenth: return [.top, .right]
        case .bottomCenterLeftSixteenth: return [.left, .top, .right]
        case .bottomCenterRightSixteenth: return [.left, .top, .right]
        case .bottomRightSixteenth: return [.left, .top]
        case .maximize: return .none
        case .leftTodo: return .right
        case .rightTodo: return .left
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
        return masShortcut.modifierFlagsString + (masShortcut.keyCodeString ?? "")
    }
}
