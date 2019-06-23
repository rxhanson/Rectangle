//
//  NextPrevThirdsCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class NextPrevThirdsCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var thirds = screenThirds(from: visibleFrameOfDestinationScreen)
        var result = thirds[0]
        for i in 0...2 {
            if rectCenteredWithinRect(thirds[i], windowRect) {
                var j = i
                if action == .nextThird {
                    j += 1
                    if j >= thirds.count {
                        j = 0
                    }
                } else if action == .previousThird {
                    j -= 1
                    if j < 0 {
                        j = thirds.count - 1
                    }
                }
                result = thirds[j]
                break
            }
        }
        return result
    }
    
    private func screenThirds(from visibleFrameOfDestinationScreen: CGRect) -> [CGRect] {
        var thirds = [CGRect]()
        for i in 0...2 {
            var third = visibleFrameOfDestinationScreen
            third.origin.x = visibleFrameOfDestinationScreen.minX + (floor(visibleFrameOfDestinationScreen.width / 3.0) * CGFloat(i))
            third.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
            thirds.append(third)
        }
        for i in 0...2 {
            var third = visibleFrameOfDestinationScreen
            third.origin.y = visibleFrameOfDestinationScreen.minY + visibleFrameOfDestinationScreen.height - (floor(visibleFrameOfDestinationScreen.height / 3.0) * CGFloat(i + 1))
            third.size.height = floor(visibleFrameOfDestinationScreen.height / 3.0)
            thirds.append(third)
        }
        return thirds
    }
}
