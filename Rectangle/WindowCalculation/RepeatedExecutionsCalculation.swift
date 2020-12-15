//
//  RepeatedExecutionsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 10/18/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

protocol RepeatedExecutionsCalculation {
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult
    
    func calculateSecondRect(_ params: RectCalculationParameters) -> RectResult

    func calculateThirdRect(_ params: RectCalculationParameters) -> RectResult

}

extension RepeatedExecutionsCalculation {
    
    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        
        guard let count = params.lastAction?.count,
              params.lastAction?.action == params.action
        else {
            return calculateFirstRect(params)
        }
                
        let position = count % 3
        
        switch (position) {
        case 1:
            return calculateSecondRect(params)
        case 2:
            return calculateThirdRect(params)
        default:
            return calculateFirstRect(params)
        }
        
    }
    
}
