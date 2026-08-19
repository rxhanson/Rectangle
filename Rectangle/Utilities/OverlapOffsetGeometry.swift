/// OverlapOffsetGeometry

import Foundation

/// Geometry handling for the overlap offset: where a window lands when it arrives
/// on a position other windows already occupy.
enum OverlapOffsetGeometry {

    /// Bounds how long a hung app can stall the overlap scan's accessibility calls.
    /// Matches the badge's timeout for the same reason.
    static let axScanTimeout: Float = 0.25

    static func applyOverlapOffsetIfNeeded(_ rect: CGRect, windowId: CGWindowID?, screen: NSScreen) -> CGRect {
        let overlapOffset = CGFloat(Defaults.cyclingOverlapOffsetSize.value)
        guard overlapOffset > 0 else { return rect }

        guard let windowId else { return rect }

        let screenFrameNormalized = screen.adjustedVisibleFrame()

        guard canOffset(rect, in: screenFrameNormalized, by: overlapOffset) else {
            return rect
        }

        // Enumerates every window over the accessibility API on the main thread.
        // Set timeout bounds to accessibility calls, so apps that are hanging or slow don't hang this.
        AXUIElementSetMessagingTimeout(AXUIElement.systemWide, Self.axScanTimeout)
        defer { AXUIElementSetMessagingTimeout(AXUIElement.systemWide, 0) }

        let screenFrameAX = screenFrameNormalized.screenFlipped
        let maxCascade = min(5, max(1, Defaults.cyclingOverlapMaxCascade.value))
        let placedCoversScreen = coversScreen(rect, screenFrame: screenFrameNormalized)

        // Each element.frame is a pair of accessibility round-trips, so the
        // frames are read once here rather than on every cascade iteration.
        let occupiedTopLefts: [CGPoint] = AccessibilityElement.getAllWindowElements().compactMap { element in
            guard element.getWindowId() != windowId,
                  element.isWindow == true,
                  element.isMinimized != true,
                  element.isHidden != true,
                  element.isSheet != true
            else { return nil }

            let frameAX = element.frame
            guard !frameAX.isNull, screenFrameAX.intersects(frameAX) else { return nil }

            // Don't let maximized windows offset all other non-maximized windows.
            let frame = frameAX.screenFlipped
            guard placedCoversScreen
                    || !coversScreen(frame, screenFrame: screenFrameNormalized)
            else { return nil }

            return topLeft(of: frame)
        }

        let offsetRect = cascadedRect(rect,
                                                           occupiedTopLefts: occupiedTopLefts,
                                                           screenFrame: screenFrameNormalized,
                                                           offset: overlapOffset,
                                                           maxCascade: maxCascade)
        if offsetRect != rect {
            Logger.log("Overlap detected, offset window to \(offsetRect.origin.debugDescription)")
        }
        return offsetRect
    }

    /// Windows are matched by their top-left corner, so that a small window
    /// landing on a larger one at the same corner still counts as an overlap.
    static func topLeft(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX, y: rect.maxY)
    }

    /// Whether a frame is large enough to count as covering the screen.
    static func coversScreen(_ rect: CGRect, screenFrame: CGRect) -> Bool {
        rect.width > screenFrame.width * 0.9 && rect.height > screenFrame.height * 0.9
    }

    /// How far the window can shift on each axis without crossing the far
    /// edge of the visible frame. Zero on an axis that has no room: shifting
    /// there anyway would push the window flush against that edge, which both
    /// hides the window underneath again and eats any gap on that side.
    static func offsetStep(for rect: CGRect, in screenFrame: CGRect, by offset: CGFloat) -> CGVector {
        CGVector(dx: rect.maxX + offset <= screenFrame.maxX ? offset : 0,
                 dy: rect.maxY + offset <= screenFrame.maxY ? offset : 0)
    }

    /// Whether the window has room to shift at all. A window sized to the
    /// whole visible frame (a maximized window with no gaps) does not, so the
    /// caller can skip scanning for overlaps entirely.
    static func canOffset(_ rect: CGRect, in screenFrame: CGRect, by offset: CGFloat) -> Bool {
        let step = offsetStep(for: rect, in: screenFrame, by: offset)
        return step.dx != 0 || step.dy != 0
    }

    /// The rect to place, shifted clear of any window already at its top-left
    /// corner, up to `maxCascade` times. Returns the rect unchanged when it
    /// overlaps nothing or has nowhere left to go.
    static func cascadedRect(_ rect: CGRect,
                             occupiedTopLefts: [CGPoint],
                             screenFrame: CGRect,
                             offset: CGFloat,
                             maxCascade: Int,
                             tolerance: CGFloat = 4) -> CGRect {
        guard offset > 0 else { return rect }
        var candidate = rect
        for _ in 0..<max(0, maxCascade) {
            let corner = topLeft(of: candidate)
            let overlaps = occupiedTopLefts.contains { occupied in
                abs(occupied.x - corner.x) < tolerance && abs(occupied.y - corner.y) < tolerance
            }
            guard overlaps else { break }

            let step = offsetStep(for: candidate, in: screenFrame, by: offset)
            guard step.dx != 0 || step.dy != 0 else { break }
            candidate.origin.x += step.dx
            candidate.origin.y += step.dy
        }
        return candidate
    }
    
}
