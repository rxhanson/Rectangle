import Cocoa
import QuartzCore

enum WindowAnimationSize {
    static func animationSize(_ requested: CGSize, origin: CGSize, hint: CGSize?) -> CGSize {
        guard let hint else { return requested }
        func axis(_ requested: CGFloat, _ origin: CGFloat, _ hint: CGFloat) -> CGFloat {
            guard hint.isFinite, hint > 0, hint <= origin + 2, requested < origin else { return requested }
            return max(requested, min(origin, hint))
        }
        return CGSize(width: axis(requested.width, origin.width, hint.width),
                      height: axis(requested.height, origin.height, hint.height))
    }
}
