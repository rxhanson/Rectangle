//
//  OrientationAware.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/23/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

typealias SimpleCalc = (_ visibleFrameOfScreen: CGRect) -> RectResult

protocol OrientationAware {
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult
    func isLandscape(_ rect: CGRect) -> Bool
    func orientationBasedRect(_ visibleFrameOfScreen: CGRect) -> RectResult
    
}

extension OrientationAware {
    func orientationBasedRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? landscapeRect(visibleFrameOfScreen)
            : portraitRect(visibleFrameOfScreen)
    }
}

