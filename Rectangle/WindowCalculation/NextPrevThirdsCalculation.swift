//
//  NextPrevThirdsCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class NextPrevThirdsCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        var thirds = screenThirds(from: visibleFrameOfScreen)
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
    
    private func screenThirds(from visibleFrameOfScreen: CGRect) -> [CGRect] {
        var thirds = [CGRect]()
        for i in 0...2 {
            var third = visibleFrameOfScreen
            third.origin.x = visibleFrameOfScreen.minX + (floor(visibleFrameOfScreen.width / 3.0) * CGFloat(i))
            third.size.width = floor(visibleFrameOfScreen.width / 3.0)
            thirds.append(third)
        }
        for i in 0...2 {
            var third = visibleFrameOfScreen
            third.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - (floor(visibleFrameOfScreen.height / 3.0) * CGFloat(i + 1))
            third.size.height = floor(visibleFrameOfScreen.height / 3.0)
            thirds.append(third)
        }
        return thirds
    }
}
