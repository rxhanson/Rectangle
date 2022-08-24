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

struct SnapAreaOption: OptionSet, Hashable {
    let rawValue: Int
    
    static let top = SnapAreaOption(rawValue: 1 << 0)
    static let bottom = SnapAreaOption(rawValue: 1 << 1)
    static let left = SnapAreaOption(rawValue: 1 << 2)
    static let right = SnapAreaOption(rawValue: 1 << 3)
    static let topLeft = SnapAreaOption(rawValue: 1 << 4)
    static let topRight = SnapAreaOption(rawValue: 1 << 5)
    static let bottomLeft = SnapAreaOption(rawValue: 1 << 6)
    static let bottomRight = SnapAreaOption(rawValue: 1 << 7)
    static let topLeftShort = SnapAreaOption(rawValue: 1 << 8)
    static let topRightShort = SnapAreaOption(rawValue: 1 << 9)
    static let bottomLeftShort = SnapAreaOption(rawValue: 1 << 10)
    static let bottomRightShort = SnapAreaOption(rawValue: 1 << 11)
    
    static let all: SnapAreaOption = [.top, .bottom, .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight, .topLeftShort, .topRightShort, .bottomLeftShort, .bottomRightShort]
    static let none: SnapAreaOption = []
}
