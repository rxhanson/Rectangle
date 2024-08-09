//
//  CycleSize.swift
//  Rectangle
//
//  Created by Eskil Gjerde Sviggum on 01/08/2024.
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

enum CycleSize: Int, CaseIterable {
    case twoThirds = 0
    case oneHalf = 1
    case oneThird = 2
    case oneQuarter = 3
    case threeQuarters = 4
    
    static func fromBits(bits: Int) -> Set<CycleSize> {
        Set(
            Self.allCases.filter {
                (bits >> $0.rawValue) & 1 == 1
            }
        )
    }
    
    static var firstSize = CycleSize.oneHalf
    static var defaultSizes: Set<CycleSize> = [.oneHalf, .twoThirds, .oneThird]
    
    // The expected order of the cycle sizes is to start with the
    // first division, then go gradually upwards in size and wrap
    // around to the smaller sizes.
    //
    // For example if all cycles are used, the order should be:
    // 1/2, 2/3, 3/4, 1/4, 1/3
    static var sortedSizes: [CycleSize] = {
        let sortedSizes = Self.allCases.sorted(by: { $0.fraction < $1.fraction })
        
        guard let firstSizeIndex = sortedSizes.firstIndex(of: firstSize) else {
            return sortedSizes
        }
        
        let lessThanFistSizes = sortedSizes[0..<firstSizeIndex]
        let greaterThanFistSizes = sortedSizes[(firstSizeIndex + 1)..<sortedSizes.count]
        
        return [firstSize] + greaterThanFistSizes + lessThanFistSizes
    }()
}

extension CycleSize {
    
    var title: String {
        switch self {
        case .twoThirds:
            "⅔"
        case .oneHalf:
            "½"
        case .oneThird:
            "⅓"
        case .oneQuarter:
            "¼"
        case .threeQuarters:
            "¾"
        }
    }
    
    var fraction: Float {
        switch self {
        case .twoThirds:
            2 / 3
        case .oneHalf:
            1 / 2
        case .oneThird:
            1 / 3
        case .oneQuarter:
            1 / 4
        case .threeQuarters:
            3 / 4
        }
    }
    
    var isAlwaysEnabled: Bool {
        if self == .firstSize {
            return true
        }
        
        return false
    }
    
}

extension Set where Element == CycleSize {
    func toBits() -> Int {
        var bits = 0
        self.forEach {
            bits |= 1 << $0.rawValue
        }
        return bits
    }
}

class CycleSizesDefault: Default {
    public private(set) var key: String = "selectedCycleSizes"
    private var initialized = false
    
    var value: Set<CycleSize> {
        didSet {
            if initialized {
                UserDefaults.standard.set(value.toBits(), forKey: key)
            }
        }
    }
    
    init() {
        let bits = UserDefaults.standard.integer(forKey: key)
        value = CycleSize.fromBits(bits: bits)
        initialized = true
    }

    func load(from codable: CodableDefault) {
        if let bits = codable.int {
            let divisions = CycleSize.fromBits(bits: bits)
            value = divisions
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(int: value.toBits())
    }

}
