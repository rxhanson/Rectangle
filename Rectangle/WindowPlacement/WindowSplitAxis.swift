import Cocoa

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
