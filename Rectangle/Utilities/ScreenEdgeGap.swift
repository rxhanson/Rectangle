//
//  ScreenEdgeGap.swift
//  Rectangle
//
//  Created by Eddie McLean on 10/9/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class ScreenEdgeGap {
    static func adjustVisibleFrame(visibleFrame: CGRect) -> CGRect {
        let topGap = CGFloat(Defaults.screenEdgeGapTop.value)
        let bottomGap = CGFloat(Defaults.screenEdgeGapBottom.value)
        let leftGap = CGFloat(Defaults.screenEdgeGapLeft.value)
        let rightGap = CGFloat(Defaults.screenEdgeGapRight.value)
        
        let origin = CGPoint(
            x: visibleFrame.origin.x + leftGap,
            y: visibleFrame.origin.y + bottomGap
        )
        let size = CGSize(
            width: visibleFrame.width - leftGap - rightGap,
            height: visibleFrame.height - topGap - bottomGap
        )
        
        return CGRect(origin: origin, size: size)
    }
}
