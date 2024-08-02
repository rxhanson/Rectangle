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
    
    func calculateRect(for cycleDivision: CycleBetweenDivision, params: RectCalculationParameters) -> RectResult

}

extension RepeatedExecutionsCalculation {
    
    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        
        guard let count = params.lastAction?.count,
              params.lastAction?.action == params.action
        else {
            return calculateFirstRect(params)
        }
        
        let useDefaultPositions = !Defaults.cycleBetweenDivisionsIsChanged.enabled
        let positions = useDefaultPositions ? CycleBetweenDivision.defaultCycleSizes : Defaults.cycleBetweenDivisions.value
        
        let sortedPositions = CycleBetweenDivision.sortedCycleDivisions
            .filter { positions.contains($0) }
                
        let position = count % sortedPositions.count
        
        return calculateRect(for: sortedPositions[position], params: params)
    }
    
}
