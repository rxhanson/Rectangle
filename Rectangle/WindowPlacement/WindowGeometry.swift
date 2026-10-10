import Cocoa

enum WindowGeometry {
    static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        !lhs.isNull && !rhs.isNull && abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
    static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite
            && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
    static func near(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        matches(lhs, rhs, tolerance: tolerance)
    }
}
