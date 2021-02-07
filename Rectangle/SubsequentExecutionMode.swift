//
//  SubsequentExecutionMode.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/15/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

enum SubsequentExecutionMode: Int {
    case resize = 0 // based on Spectacle
    case acrossMonitor = 1
    case none = 2
    case acrossAndResize = 3 // across monitor for right/left, spectacle resize for all else
    case cycleMonitor = 4 // moves window to same (normalized) position on next monitor
}

class SubsequentExecutionDefault: Default {
    public private(set) var key: String = "subsequentExecutionMode"
    private var initialized = false
    
    var value: SubsequentExecutionMode {
        didSet {
            if initialized {
                UserDefaults.standard.set(value.rawValue, forKey: key)
            }
        }
    }
    
    init() {
        let intValue = UserDefaults.standard.integer(forKey: key)
        value = SubsequentExecutionMode(rawValue: intValue) ?? .resize
        initialized = true
    }
    
    var resizes: Bool {
        switch value {
        case .resize, .acrossAndResize: return true
        default: return false
        }
    }

    var traversesDisplays: Bool {
        switch value {
        case .acrossMonitor, .acrossAndResize: return true
        default: return false
        }
    }

    func load(from codable: CodableDefault) {
        if let int = codable.int,
           let mode = SubsequentExecutionMode(rawValue: int) {
            value = mode
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(int: value.rawValue)
    }

}
