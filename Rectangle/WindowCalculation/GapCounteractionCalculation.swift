//
//  GapCounteractionCalculation.swift
//  Rectangle
//
//  Created by Charlie Harding on 12/05/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

protocol GapCounteractionCalculation {
    
}

extension GapCounteractionCalculation {
    
    /// Increase the width of a window such that it will return to its original position when the gaps are added back in. This does not take into account shared gaps, and if an edge is close to the edge of the screen, the window will shrink accordingly.
    /// - Parameters:
    ///   - calculatedWindowRect: The existing size of the window, which should be maintained after the gaps are added back in.
    ///   - visibleFrameOfScreen: The boundaries of the screen. This used to ensure that the window will occupy no more that its current horizontal bounds, but the gaps at the edge of the screen will be respected.
    /// - Returns: An updated, larger window size that will shrink to the original width once the gaps are reapplied.
    func counteractHorizontalGaps(_ calculatedWindowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> CGRect {
        
        let gapSize = CGFloat(Defaults.gapSize.value)
        let leftGap = min(calculatedWindowRect.minX - visibleFrameOfScreen.minX, gapSize)
        let rightGap = min(visibleFrameOfScreen.maxX - calculatedWindowRect.maxX, gapSize)
        
        var adjustedWindowRect = calculatedWindowRect
        
        adjustedWindowRect.size.width += leftGap + rightGap
        adjustedWindowRect.origin.x -= leftGap
        
        return adjustedWindowRect
        
    }
    
}
