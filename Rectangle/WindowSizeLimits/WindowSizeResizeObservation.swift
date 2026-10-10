import Cocoa

/// Samples contain only agreeing AX/WindowServer frames. A stable oversized
/// response is evidence only when the requested axis actually shrank.
struct WindowSizeResizeObservation {
    let before: CGRect
    let requested: CGRect
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(before: CGRect, requested: CGRect) {
        self.before = before
        self.requested = requested
    }

    mutating func observe(_ frame: CGRect?, at time: TimeInterval) -> CGRect? {
        guard let frame, WindowAnimationGeometry.valid(frame),
              WindowAnimationGeometry.valid(before), WindowAnimationGeometry.valid(requested),
              WindowGeometry.matches(frame, requested, tolerance: 1)
                || (Self.learnedMinimum(before: before.size, requested: requested.size, settled: frame.size) != nil
                    && frame.minX <= requested.minX + 1 && frame.maxX >= requested.maxX - 1
                    && frame.minY <= requested.minY + 1 && frame.maxY >= requested.maxY - 1) else {
            previous = nil; stableSince = nil
            return nil
        }
        guard let previous, WindowGeometry.matches(frame, previous, tolerance: 1) else {
            self.previous = frame
            stableSince = time
            return nil
        }
        guard let stableSince, time - stableSince >= 0.12 else { return nil }
        return frame
    }

    static func learnedMinimum(before: CGSize, requested: CGSize, settled: CGSize) -> CGSize? {
        func clamp(_ old: CGFloat, _ target: CGFloat, _ actual: CGFloat) -> CGFloat {
            // An unchanged dimension can be an ignored write. Coupled changes
            // can be an aspect ratio or a sizing grid rather than a minimum.
            target + 2 < actual && actual < old - 1 ? actual : 0
        }
        let learned = CGSize(width: clamp(before.width, requested.width, settled.width),
                             height: clamp(before.height, requested.height, settled.height))
        guard (learned.width > 0) != (learned.height > 0),
              learned.width > 0 ? abs(requested.height - settled.height) <= 1
                                : abs(requested.width - settled.width) <= 1 else { return nil }
        return learned
    }
}
/// Warning-only sampling uses WindowServer geometry so a stalled target app
/// cannot block the main run loop after an otherwise completed action.
enum WindowSizeWarningObservation {
    struct Source {
        let frame: () -> CGRect?
        let isCurrent: () -> Bool
    }

    static func sample(frame: @escaping () -> CGRect?, isCurrent: @escaping () -> Bool,
                       completion: @escaping (CGRect) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard isCurrent(), let first = frame() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard isCurrent(), let settled = frame(),
                      WindowGeometry.matches(first, settled, tolerance: 1) else { return }
                completion(settled)
            }
        }
    }
}
final class WindowSizeWarningIcon: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.scaleX(by: bounds.width / 48, yBy: bounds.height / 36)
        transform.concat()
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        let outline = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 48, height: 36).insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        outline.lineWidth = 2
        outline.stroke()

        let arrows = NSBezierPath()
        arrows.lineWidth = 2.5
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        arrows.move(to: NSPoint(x: 14, y: 26))
        arrows.line(to: NSPoint(x: 22, y: 18))
        arrows.move(to: NSPoint(x: 16, y: 18))
        arrows.line(to: NSPoint(x: 22, y: 18))
        arrows.line(to: NSPoint(x: 22, y: 24))
        arrows.move(to: NSPoint(x: 34, y: 10))
        arrows.line(to: NSPoint(x: 26, y: 18))
        arrows.move(to: NSPoint(x: 26, y: 12))
        arrows.line(to: NSPoint(x: 26, y: 18))
        arrows.line(to: NSPoint(x: 32, y: 18))
        arrows.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
