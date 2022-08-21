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
    
    static let defaultHorizontal: [Directional:SnapAreaConfig] = [
        .tl: SnapAreaConfig(action: .topLeft),
        .t: SnapAreaConfig(action: .maximize),
        .tr: SnapAreaConfig(action: .topRight),
        .l: SnapAreaConfig(complex: .leftTopBottomHalf),
        .r: SnapAreaConfig(complex: .rightTopBottomHalf),
        .bl: SnapAreaConfig(action: .bottomLeft),
        .b: SnapAreaConfig(complex: .thirds),
        .br: SnapAreaConfig(action: .bottomRight)
    ]
    
    static let defaultVertical: [Directional:SnapAreaConfig] = [
        .tl: SnapAreaConfig(action: .topLeft),
        .t: SnapAreaConfig(action: .maximize),
        .tr: SnapAreaConfig(action: .topRight),
        .l: SnapAreaConfig(complex: .leftTopBottomHalf),
        .r: SnapAreaConfig(complex: .rightTopBottomHalf),
        .bl: SnapAreaConfig(action: .topLeft),
        .b: SnapAreaConfig(complex: .thirds),
        .br: SnapAreaConfig(action: .topLeft)
    ]
    
    public private(set) var horizontal: [Directional:SnapAreaConfig] = Defaults.horizontalSnapAreas.typedValue ?? SnapAreaModel.defaultHorizontal
    public private(set) var vertical: [Directional:SnapAreaConfig] = Defaults.verticalSnapAreas.typedValue ?? SnapAreaModel.defaultVertical
    
    func setConfig(type: SnapAreaModelType, directional: Directional, snapAreaConfig: SnapAreaConfig?) {
        switch type {
        case .horizontal: setHorizontal(directional: directional, snapAreaConfig: snapAreaConfig)
        case .vertical: setVertical(directional: directional, snapAreaConfig: snapAreaConfig)
        }
    }
    
    func setHorizontal(directional: Directional, snapAreaConfig: SnapAreaConfig?) {
        horizontal[directional] = snapAreaConfig
        Defaults.horizontalSnapAreas.typedValue = horizontal
    }
    
    func setVertical(directional: Directional, snapAreaConfig: SnapAreaConfig?) {
        vertical[directional] = snapAreaConfig
        Defaults.verticalSnapAreas.typedValue = vertical
    }
}

enum SnapAreaModelType {
    case vertical, horizontal
}
