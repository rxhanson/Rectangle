//
//  SnapAreaModel.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/19/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class SnapAreaModel {
    static let instance = SnapAreaModel()
    
    private init() {}
    
    static let defaultLandscape: [Directional:SnapAreaConfig] = [
        .tl: SnapAreaConfig(action: .topLeft),
        .t: SnapAreaConfig(action: .maximize),
        .tr: SnapAreaConfig(action: .topRight),
        .l: SnapAreaConfig(compound: .leftTopBottomHalf),
        .r: SnapAreaConfig(compound: .rightTopBottomHalf),
        .bl: SnapAreaConfig(action: .bottomLeft),
        .b: SnapAreaConfig(compound: .thirds),
        .br: SnapAreaConfig(action: .bottomRight)
    ]
    
    static let defaultPortrait: [Directional:SnapAreaConfig] = [
        .tl: SnapAreaConfig(action: .topLeft),
        .t: SnapAreaConfig(action: .maximize),
        .tr: SnapAreaConfig(action: .topRight),
        .l: SnapAreaConfig(compound: .portraitThirdsSide),
        .r: SnapAreaConfig(compound: .portraitThirdsSide),
        .bl: SnapAreaConfig(action: .bottomLeft),
        .b: SnapAreaConfig(compound: .halves),
        .br: SnapAreaConfig(action: .bottomRight)
    ]
    
    public private(set) var landscape: [Directional:SnapAreaConfig] = Defaults.landscapeSnapAreas.typedValue ?? SnapAreaModel.defaultLandscape
    public private(set) var portrait: [Directional:SnapAreaConfig] = Defaults.portraitSnapAreas.typedValue ?? SnapAreaModel.defaultPortrait
    
    func setConfig(type: DisplayOrientation, directional: Directional, snapAreaConfig: SnapAreaConfig?) {
        switch type {
        case .landscape: setLandscape(directional: directional, snapAreaConfig: snapAreaConfig)
        case .portrait: setPortrait(directional: directional, snapAreaConfig: snapAreaConfig)
        }
    }
    
    func setLandscape(directional: Directional, snapAreaConfig: SnapAreaConfig?) {
        landscape[directional] = snapAreaConfig
        Defaults.landscapeSnapAreas.typedValue = landscape
    }
    
    func setPortrait(directional: Directional, snapAreaConfig: SnapAreaConfig?) {
        portrait[directional] = snapAreaConfig
        Defaults.portraitSnapAreas.typedValue = portrait
    }
}

enum DisplayOrientation {
    case landscape, portrait
}

enum CompoundSnapArea: Int, Codable {
    case leftTopBottomHalf = -1, rightTopBottomHalf = -2, thirds = -3, portraitThirdsSide = -4, halves = -5
    
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
        }
    }
    
    static let all = [leftTopBottomHalf, rightTopBottomHalf, thirds, portraitThirdsSide, halves]
    
    var compatibleDirectionals: [Directional] {
        switch self {
        case .leftTopBottomHalf: return [.l]
        case .rightTopBottomHalf: return [.r]
        case .thirds: return [.t, .b]
        case .portraitThirdsSide: return [.l, .r]
        case .halves: return [.t, .b]
        }
    }
    
    var compatibleOrientation: [DisplayOrientation] {
        switch self {
        case .leftTopBottomHalf, .rightTopBottomHalf, .halves: return [.portrait, .landscape]
        case .portraitThirdsSide: return [.portrait]
        case .thirds: return [.landscape]
        }
    }
}

struct SnapAreaConfig: Codable {
    let compound: CompoundSnapArea?
    let action: WindowAction?
    
    init(compound: CompoundSnapArea? = nil, action: WindowAction? = nil) {
        self.compound = compound
        self.action = action
    }
}

enum Directional: Int, Codable {
    case tl = 1,
         t = 2,
         tr = 3,
         l = 4,
         r = 5,
         bl = 6,
         b = 7,
         br = 8,
         c = 9
    
    static var cases = [tl, t, tr, l, r, bl, b, br]
}
