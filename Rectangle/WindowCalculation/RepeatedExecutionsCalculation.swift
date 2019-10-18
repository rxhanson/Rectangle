//
//  SubsequentThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 10/18/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

protocol RepeatedExecutionsCalculation {
    
    func calculateFirstRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect
    
    func calculateSecondRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect

    func calculateThirdRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect

}

extension RepeatedExecutionsCalculation {
    
    func calculateRepeatedRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect {
        
        guard let count = lastAction?.count,
            lastAction?.action == action
        else {
            return calculateFirstRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
                
        let position = count % 3
        
        switch (position) {
        case 1:
            return calculateSecondRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        case 2:
            return calculateThirdRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        default:
            return calculateFirstRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
    }
    
}
