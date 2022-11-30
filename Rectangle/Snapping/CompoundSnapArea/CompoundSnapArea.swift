//
//  CompoundSnapArea.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/23/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

enum CompoundSnapArea: Int, Codable {
    
    case leftTopBottomHalf = -2, rightTopBottomHalf = -3, thirds = -4, portraitThirdsSide = -5, halves = -6, topSixths = -7, bottomSixths = -8, fourths = -9
    
    static let all = [leftTopBottomHalf, rightTopBottomHalf, thirds, portraitThirdsSide, halves, topSixths, bottomSixths, fourths]
    
    static let leftCompoundCalculation = LeftTopBottomHalfCalculation()
    static let rightCompoundCalculation = RightTopBottomHalfCalculation()
    static let thirdsCompoundCalculation = ThirdsCompoundCalculation()
    static let portraitSideThirdsCalculation = PortraitSideThirdsCompoundCalculation()
    static let leftRightHalvesCalculation = LeftRightHalvesCompoundCalculation()
    static let topSixthsCalculation = TopSixthsCompoundCalculation()
    static let bottomSixthsCalculation = BottomSixthsCompoundCalculation()
    static let fourthsColumnCalculation = FourthsColumnCompoundCalculation()

    var displayName: String {
        switch self {
        case .leftTopBottomHalf:
            return NSLocalizedString("Left half, top/bottom half near corners", tableName: "Main", value: "", comment: "")
        case .rightTopBottomHalf:
            return NSLocalizedString("Right half, top/bottom half near corners", tableName: "Main", value: "", comment: "")
        case .thirds:
            return NSLocalizedString("Thirds, drag toward center for two thirds", tableName: "Main", value: "", comment: "")
        case .portraitThirdsSide:
            return NSLocalizedString("Thirds, top/bottom half near corners", tableName: "Main", value: "", comment: "")
        case .halves:
            return NSLocalizedString("Left or right half", tableName: "Main", value: "", comment: "")
        case .topSixths:
            return NSLocalizedString("Top sixths from corners; maximize", tableName: "Main", value: "", comment: "")
        case .bottomSixths:
            return NSLocalizedString("Bottom sixths from corners; thirds", tableName: "Main", value: "", comment: "")
        case .fourths:
            return NSLocalizedString("Fourths columns", tableName: "Main", value: "", comment: "")
        }
    }
    
    var calculation: CompoundSnapAreaCalculation {
        switch self {
        case .leftTopBottomHalf:
            return Self.leftCompoundCalculation
        case .rightTopBottomHalf:
            return Self.rightCompoundCalculation
        case .thirds:
            return Self.thirdsCompoundCalculation
        case .portraitThirdsSide:
            return Self.portraitSideThirdsCalculation
        case .halves:
            return Self.leftRightHalvesCalculation
        case .topSixths:
            return Self.topSixthsCalculation
        case .bottomSixths:
            return Self.bottomSixthsCalculation
        case .fourths:
            return Self.fourthsColumnCalculation
        }
    }
    
    var compatibleDirectionals: [Directional] {
        switch self {
        case .leftTopBottomHalf:
            return [.l]
        case .rightTopBottomHalf:
            return [.r]
        case .thirds:
            return [.t, .b]
        case .portraitThirdsSide:
            return [.l, .r]
        case .halves:
            return [.t, .b]
        case .topSixths:
            return [.t]
        case .bottomSixths:
            return [.b]
        case .fourths:
            return [.t, .b]
        }
    }
    
    var compatibleOrientation: [DisplayOrientation] {
        switch self {
        case .leftTopBottomHalf, .rightTopBottomHalf, .halves:
            return [.portrait, .landscape]
        case .portraitThirdsSide:
            return [.portrait]
        case .thirds, .topSixths, .bottomSixths, .fourths:
            return [.landscape]
        }
    }
}

protocol CompoundSnapAreaCalculation {
    func snapArea(cursorLocation: NSPoint, screen: NSScreen, directional: Directional, priorSnapArea: SnapArea?) -> SnapArea?
}
