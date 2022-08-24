//
//  CompoundSnapArea.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/23/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

enum CompoundSnapArea: Int, Codable {
    
    case leftTopBottomHalf = -1, rightTopBottomHalf = -2, thirds = -3, portraitThirdsSide = -4, halves = -5, topSixths = -6, bottomSixths = -7
    
    static let all = [leftTopBottomHalf, rightTopBottomHalf, thirds, portraitThirdsSide, halves, topSixths, bottomSixths]
    
    static let leftCompoundCalculation = LeftTopBottomHalfCalculation()
    static let rightCompoundCalculation = RightTopBottomHalfCalculation()
    static let thirdsCompoundCalculation = ThirdsCompoundCalculation()
    static let portraitSideThirdsCalculation = PortraitSideThirdsCompoundCalculation()
    static let leftRightHalvesCalculation = LeftRightHalvesCompoundCalculation()
    static let topSixthsCalculation = TopSixthsCompoundCalculation()
    static let bottomSixthsCalculation = BottomSixthsCompoundCalculation()
    
    var displayName: String {
        switch self {
        case .leftTopBottomHalf:
            return "Left half, top/bottom half near corners"
        case .rightTopBottomHalf:
            return "Right half, top/bottom half near corners"
        case .thirds:
            return "Thirds, drag toward center for two thirds"
        case .portraitThirdsSide:
            return "Thirds, top/bottom half near corners"
        case .halves:
            return "Left or right half"
        case .topSixths:
            return "Top sixths from corners or maximize"
        case .bottomSixths:
            return "Bottom sixths from corners or thirds"
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
        }
    }
    
    var compatibleOrientation: [DisplayOrientation] {
        switch self {
        case .leftTopBottomHalf, .rightTopBottomHalf, .halves: return [.portrait, .landscape]
        case .portraitThirdsSide: return [.portrait]
        case .thirds, .topSixths, .bottomSixths: return [.landscape]
        }
    }
}

protocol CompoundSnapAreaCalculation {
    func snapArea(cursorLocation: NSPoint, screen: NSScreen, priorSnapArea: SnapArea?) -> SnapArea?
}
