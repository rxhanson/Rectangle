//
//  CycleBetweenDivisions.swift
//  Rectangle
//
//  Created by Eskil Gjerde Sviggum on 01/08/2024.
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

enum CycleBetweenDivision: Int, CaseIterable {
    case twoThirds = 0
    case oneHalf = 1
    case oneThird = 2
    case oneQuarter = 3
    case threeQuarters = 4
    
    static func fromBits(bits: Int) -> Set<CycleBetweenDivision> {
        Set(
            Self.allCases.filter {
                (bits >> $0.rawValue) & 1 == 1
            }
        )
    }
    
    static var firstDivision = CycleBetweenDivision.oneHalf
    static var defaultCycleSizes: Set<CycleBetweenDivision> = [.oneHalf, .oneThird, .twoThirds]
    
    // The expected order of the cycle sizes is to start with the
    // first division, then go gradually downwards in size and wrap
    // around to the larger sizes.
    //
    // For example if all cycles are used, the order should be:
    // 1/2, 1/3, 1/4, 3/4, 2/3
    static var sortedCycleDivisions: [CycleBetweenDivision] = {
        let sortedDivisions = Self.allCases.sorted(by: { $0.fraction < $1.fraction })
        
        guard let firstDivisionIndex = sortedDivisions.firstIndex(of: firstDivision) else {
            return sortedDivisions
        }
        
        let lessThanFistDivision = sortedDivisions[0..<firstDivisionIndex]
        let greaterThanFistDivision = sortedDivisions[(firstDivisionIndex + 1)..<sortedDivisions.count]
        
        return [firstDivision] + lessThanFistDivision.reversed() + greaterThanFistDivision.reversed()
    }()
}

extension CycleBetweenDivision {
    
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
        if self == .firstDivision {
            return true
        }
        
        return false
    }
    
}

extension Set where Element == CycleBetweenDivision {
    func toBits() -> Int {
        var bits = 0
        self.forEach {
            bits |= 1 << $0.rawValue
        }
        return bits
    }
}

class CycleBetweenDivisionsDefault: Default {
    public private(set) var key: String = "cycleBetweenDivisions"
    private var initialized = false
    
    var value: Set<CycleBetweenDivision> {
        didSet {
            if initialized {
                UserDefaults.standard.set(value.toBits(), forKey: key)
            }
        }
    }
    
    init() {
        let bits = UserDefaults.standard.integer(forKey: key)
        value = CycleBetweenDivision.fromBits(bits: bits)
        initialized = true
    }

    func load(from codable: CodableDefault) {
        if let bits = codable.int {
            let divisions = CycleBetweenDivision.fromBits(bits: bits)
            value = divisions
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(int: value.toBits())
    }

}
