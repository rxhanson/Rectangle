//
//  Mouse.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import CoreGraphics

struct Mouse {
    static func currentPosition() -> CGPoint? {
        return CGEvent(source: nil)?.location
    }
}
