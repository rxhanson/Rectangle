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
        .l: SnapAreaConfig(complex: .leftTopBottomHalf),
        .r: SnapAreaConfig(complex: .rightTopBottomHalf),
        .bl: SnapAreaConfig(action: .bottomLeft),
        .b: SnapAreaConfig(complex: .thirds),
        .br: SnapAreaConfig(action: .bottomRight)
    ]
    
    static let defaultPortrait: [Directional:SnapAreaConfig] = [
        .tl: SnapAreaConfig(action: .topLeft),
        .t: SnapAreaConfig(action: .maximize),
        .tr: SnapAreaConfig(action: .topRight),
        .l: SnapAreaConfig(complex: .leftTopBottomHalf),
        .r: SnapAreaConfig(complex: .rightTopBottomHalf),
        .bl: SnapAreaConfig(action: .topLeft),
        .b: SnapAreaConfig(complex: .thirds),
        .br: SnapAreaConfig(action: .topLeft)
    ]
    
    public private(set) var landscape: [Directional:SnapAreaConfig] = Defaults.landscapeSnapAreas.typedValue ?? SnapAreaModel.defaultLandscape
    public private(set) var portrait: [Directional:SnapAreaConfig] = Defaults.portraitSnapAreas.typedValue ?? SnapAreaModel.defaultPortrait
    
    func setConfig(type: SnapAreaModelType, directional: Directional, snapAreaConfig: SnapAreaConfig?) {
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

enum SnapAreaModelType {
    case landscape, portrait
}
