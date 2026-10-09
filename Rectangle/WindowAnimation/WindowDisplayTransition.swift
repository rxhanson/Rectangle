import Cocoa
import QuartzCore

enum WindowDisplayTransition {
    static func display(containing frame: CGRect, displays: [CGRect]) -> CGRect? {
        displays.filter { $0.intersects(frame) }.max {
            let a = $0.intersection(frame), b = $1.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
    }

    static func crossesDisplays(from source: CGRect, to destination: CGRect) -> Bool {
        let frames = NSScreen.screens.map { $0.frame.screenFlipped }
        guard let a = WindowDisplayTransition.display(containing: source, displays: frames),
              let b = WindowDisplayTransition.display(containing: destination, displays: frames) else { return false }
        return a != b
    }
}
