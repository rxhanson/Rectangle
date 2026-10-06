import CoreFoundation
import Foundation
import IOKit

protocol TrackpadTouchSource: AnyObject {
    var onDeviceOverlap: (() -> Void)? { get set }
    var onContactCount: ((Int) -> Void)? { get set }
    var onFrame: ((TrackpadTouchFrame) -> Void)? { get set }
    var deviceCount: Int { get }
    func start()
    func stop()
}
