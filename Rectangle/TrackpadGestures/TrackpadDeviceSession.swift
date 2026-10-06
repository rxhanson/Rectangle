import CoreFoundation
import Foundation
import IOKit

// A second trackpad must lift before it can claim a fresh session after the current owner.
struct TrackpadDeviceSession {
    private var owner: UInt?
    private var waitingForLift = Set<UInt>()

    mutating func accepts(device: UInt, contacts: Int) -> Bool {
        if owner == device {
            if contacts == 0 { owner = nil }
            return true
        }
        if contacts == 0 {
            waitingForLift.remove(device)
            return false
        }
        guard owner == nil, waitingForLift.isEmpty else {
            waitingForLift.insert(device)
            return false
        }
        owner = device
        return true
    }
}
