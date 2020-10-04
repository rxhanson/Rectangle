//
//  WindowActionCategory.swift
//  Rectangle
//
//  Created by Ryan Hanson on 10/3/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

enum WindowActionCategory {

    case halves, corners, thirds, max, size, display, move, other, sixths, fourths
    
    var displayName: String {
        switch self {
        case .halves: return "Halves"
        case .corners: return "Corners"
        case .thirds: return "Thirds"
        case .max: return "Maximize"
        case .size: return "Size"
        case .display: return "Display"
        case .other: return "Other"
        case .move: return "Move to Edge"
        case .fourths: return "Fourths"
        case .sixths: return "Sixths"
        }
    }
}
