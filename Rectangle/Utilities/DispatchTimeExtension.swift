/// DispatchTimeExtension.swift

import Foundation

extension DispatchTime {
    var uptimeMilliseconds: UInt64 { uptimeNanoseconds / 1_000_000 }
}
