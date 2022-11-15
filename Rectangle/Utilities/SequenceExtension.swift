//
//  SequenceExtension.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

extension Sequence {
    func uniqueMap<T>(_ transform: (Element) -> T) -> [T] where T: Hashable {
        var set = Set<T>()
        var array = Array<T>()
        for element in self {
            let element = transform(element)
            if set.insert(element).inserted {
                array.append(element)
            }
        }
        return array
    }
}
