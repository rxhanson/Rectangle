import Cocoa

enum WindowGeometry {
    static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        !lhs.isNull && !rhs.isNull && abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}

enum WindowSplitAxis {
    case horizontal, vertical
    init?(action: WindowAction) {
        switch action {
        case .leftHalf, .rightHalf: self = .horizontal
        case .topHalf, .bottomHalf: self = .vertical
        default: return nil
        }
    }
    func rect(_ r: CGRect) -> CGRect {
        self == .horizontal ? r : CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width)
    }
    func size(_ s: CGSize) -> CGSize { self == .horizontal ? s : CGSize(width: s.height, height: s.width) }
    func coordinate(_ p: CGPoint) -> CGFloat { self == .horizontal ? p.x : p.y }
    func point(_ primary: CGFloat, cross: CGFloat) -> CGPoint {
        self == .horizontal ? CGPoint(x: primary, y: cross) : CGPoint(x: cross, y: primary)
    }
}
