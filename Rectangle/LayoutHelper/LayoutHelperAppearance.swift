import Cocoa

enum LayoutHelperAppearance {
    static let cornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 10
    static let outline = NSColor(calibratedWhite: 0.76, alpha: 1)
    static let selection = NSColor(calibratedWhite: 0.62, alpha: 1)

    private static let cardCurve: (points: [CGPoint], tangents: [CGPoint], chords: [CGFloat]) = {
        let segments = 6
        let exponent: CGFloat = 2 / 2.1
        let points = (0...segments).map { index -> CGPoint in
            if index == 0 { return CGPoint(x: 0, y: 1) }
            if index == segments { return CGPoint(x: 1, y: 0) }
            let angle = CGFloat(index) * .pi / (2 * CGFloat(segments))
            return CGPoint(x: pow(sin(angle), exponent), y: pow(cos(angle), exponent))
        }
        let tangents = (0...segments).map { index -> CGPoint in
            if index == 0 { return CGPoint(x: 1, y: 0) }
            if index == segments { return CGPoint(x: 0, y: -1) }
            let angle = CGFloat(index) * .pi / (2 * CGFloat(segments))
            let x = pow(sin(angle), exponent - 1) * cos(angle)
            let y = -pow(cos(angle), exponent - 1) * sin(angle)
            let length = sqrt(x * x + y * y)
            return CGPoint(x: x / length, y: y / length)
        }
        let chords = (0..<segments).map { index -> CGFloat in
            let dx = points[index + 1].x - points[index].x
            let dy = points[index + 1].y - points[index].y
            return sqrt(dx * dx + dy * dy)
        }
        return (points, tangents, chords)
    }()

    static func cardPath(in rect: CGRect, radius: CGFloat = cardCornerRadius) -> CGPath {
        let radius = max(0, min(radius, min(rect.width, rect.height) / 2))
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        let (points, tangents, chords) = cardCurve
        let segments = chords.count
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))

        func corner(center: CGPoint, rotation: Int) {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let rotated: (CGFloat, CGFloat)
                switch rotation {
                case 1: rotated = (y, -x)
                case 2: rotated = (-x, -y)
                case 3: rotated = (-y, x)
                default: rotated = (x, y)
                }
                return CGPoint(x: center.x + rotated.0 * radius,
                               y: center.y + rotated.1 * radius)
            }
            for index in 0..<segments {
                let start = points[index]
                let end = points[index + 1]
                let startHandle = (index == 0 ? chords[0] : min(chords[index - 1], chords[index])) / 3
                let endHandle = (index == segments - 1 ? chords[index] : min(chords[index], chords[index + 1])) / 3
                path.addCurve(
                    to: point(end.x, end.y),
                    control1: point(start.x + tangents[index].x * startHandle,
                                    start.y + tangents[index].y * startHandle),
                    control2: point(end.x - tangents[index + 1].x * endHandle,
                                    end.y - tangents[index + 1].y * endHandle)
                )
            }
        }

        corner(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), rotation: 0)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        corner(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), rotation: 1)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        corner(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), rotation: 2)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        corner(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), rotation: 3)
        path.closeSubpath()
        return path
    }
}
