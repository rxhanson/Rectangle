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
    
    func calculateRect(for cycleDivision: CycleSize, params: RectCalculationParameters) -> RectResult

}

extension RepeatedExecutionsCalculation {
    
    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        
        guard let count = params.lastAction?.count,
              params.lastAction?.action == params.action
        else {
            return calculateFirstRect(params)
        }
        
        let useDefaultPositions = !Defaults.cycleSizesIsChanged.enabled
        let positions = useDefaultPositions ? CycleSize.defaultSizes : Defaults.selectedCycleSizes.value
        
        let sortedPositions = CycleSize.sortedSizes
            .filter { positions.contains($0) }
                
        let position = count % sortedPositions.count
        
        return calculateRect(for: sortedPositions[position], params: params)
    }
    
}
