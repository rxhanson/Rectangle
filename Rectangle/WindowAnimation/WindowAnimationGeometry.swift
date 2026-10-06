import Cocoa
import QuartzCore

enum WindowAnimationGeometry {
    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } && frame.width > 0 && frame.height > 0
    }
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        valid(a) && valid(b) && abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance && abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
}
