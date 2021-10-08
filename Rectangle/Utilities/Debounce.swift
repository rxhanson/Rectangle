//
//  Debounce.swift
//  Rectangle
//
//  Created by Ryan Hanson on 10/7/21.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//

import Foundation
import Dispatch

class Debounce<T: Equatable> {

    private init() {}

    static func input(_ input: T,
                      comparedAgainst current: @escaping @autoclosure () -> (T),
                      perform: @escaping (T) -> ()) {

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if input == current() { perform(input) }
        }
    }
}
