/// FreeformDrag.swift

import CoreGraphics

/// The geometry of a screenshot-style area selection, in AppKit screen coordinates.
///
/// The point where the drag starts stays fixed and the pointer moves the opposite corner.
/// As in the macOS screenshot selection, holding Space moves the whole selection, Option
/// resizes it around the starting point, and Shift locks the side the pointer moves least
/// after Shift is pressed. The selection never leaves `bounds`, and its edges are whole points.
struct FreeformDrag {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int

        /// Space: move the selection without resizing it.
        static let move = Modifiers(rawValue: 1 << 0)
        /// Option: resize the selection around the point where the drag started.
        static let fromCenter = Modifiers(rawValue: 1 << 1)
        /// Shift: resize along one axis only.
        static let lockAxis = Modifiers(rawValue: 1 << 2)
    }

    private enum Axis {
        case horizontal, vertical
    }

    /// Smaller selections are treated as clicks.
    static let minimumSize: CGFloat = 8
    /// How far the pointer moves after Shift is pressed before an axis is locked.
    static let lockThreshold: CGFloat = 4
    /// The pointer can't reach a display's right edge, or its bottom edge in AppKit
    /// coordinates (y is 0 below the last pixel row), so edges this close to the bounds snap to them.
    static let edgeSnapDistance: CGFloat = 1

    let bounds: CGRect
    private(set) var rect: CGRect

    /// The fixed corner, or the center with Option. Always inside `bounds`.
    private var anchor: CGPoint
    private var pointer: CGPoint
    /// The moving corner is `pointer + offset`. Moving the selection, or locking an axis,
    /// changes the offset so the corner doesn't jump when Space or Shift is released.
    private var offset = CGVector.zero
    /// The moving corner when Shift was pressed, and the axis frozen at it.
    private var shiftStart: (pointer: CGPoint, corner: CGPoint)?
    private var frozenAxis: Axis?

    var isLargeEnough: Bool {
        rect.width >= Self.minimumSize && rect.height >= Self.minimumSize
    }

    init(start: CGPoint, bounds: CGRect) {
        self.bounds = bounds
        anchor = Self.clamped(start, to: bounds)
        // Starting outside the bounds (on the menu bar, say) starts from their edge.
        pointer = anchor
        rect = Self.snapped(CGRect(origin: anchor, size: .zero), within: bounds)
    }

    mutating func update(to point: CGPoint, modifiers: Modifiers = []) {
        let fromCenter = modifiers.contains(.fromCenter)
        if modifiers.contains(.move) {
            move(to: point, fromCenter: fromCenter)
            // Shift locks the axis anew once the selection stops moving.
            shiftStart = nil
            frozenAxis = nil
        } else {
            pointer = point
            updateAxisLock(isShiftDown: modifiers.contains(.lockAxis))
        }
        rect = Self.snapped(span(fromCenter: fromCenter), within: bounds)
    }

    /// The selected area, or nil when the drag was too small to be more than a click.
    mutating func finish(at point: CGPoint, modifiers: Modifiers = []) -> CGRect? {
        update(to: point, modifiers: modifiers)
        return isLargeEnough ? rect : nil
    }

    // MARK: - Geometry

    private var corner: CGPoint {
        CGPoint(x: pointer.x + offset.dx, y: pointer.y + offset.dy)
    }

    /// The moving corner, limited so that the selection stays inside the bounds.
    private func visibleCorner(fromCenter: Bool) -> CGPoint {
        guard fromCenter else { return Self.clamped(corner, to: bounds) }
        let maxX = min(anchor.x - bounds.minX, bounds.maxX - anchor.x)
        let maxY = min(anchor.y - bounds.minY, bounds.maxY - anchor.y)
        return CGPoint(x: anchor.x + min(max(corner.x - anchor.x, -maxX), maxX),
                       y: anchor.y + min(max(corner.y - anchor.y, -maxY), maxY))
    }

    private func span(fromCenter: Bool) -> CGRect {
        let end = visibleCorner(fromCenter: fromCenter)
        if fromCenter {
            let dx = abs(end.x - anchor.x), dy = abs(end.y - anchor.y)
            return CGRect(x: anchor.x - dx, y: anchor.y - dy, width: dx * 2, height: dy * 2)
        }
        return CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y),
                      width: abs(end.x - anchor.x), height: abs(end.y - anchor.y))
    }

    private mutating func move(to point: CGPoint, fromCenter: Bool) {
        let current = span(fromCenter: fromCenter)
        let end = visibleCorner(fromCenter: fromCenter)
        // Stop at the bounds instead of shrinking the selection.
        let dx = min(max(point.x - pointer.x, bounds.minX - current.minX), bounds.maxX - current.maxX)
        let dy = min(max(point.y - pointer.y, bounds.minY - current.minY), bounds.maxY - current.maxY)
        anchor.x += dx
        anchor.y += dy
        pointer = point
        offset = CGVector(dx: end.x + dx - point.x, dy: end.y + dy - point.y)
    }

    private mutating func updateAxisLock(isShiftDown: Bool) {
        guard isShiftDown else {
            shiftStart = nil
            frozenAxis = nil
            return
        }
        guard let start = shiftStart else {
            shiftStart = (pointer, corner)
            return
        }
        if frozenAxis == nil {
            let dx = abs(pointer.x - start.pointer.x), dy = abs(pointer.y - start.pointer.y)
            guard max(dx, dy) >= Self.lockThreshold, dx != dy else { return }
            frozenAxis = dx > dy ? .vertical : .horizontal
        }
        switch frozenAxis {
        case .vertical: offset.dy = start.corner.y - pointer.y
        case .horizontal: offset.dx = start.corner.x - pointer.x
        case nil: break
        }
    }

    private static func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY))
    }

    private static func snapped(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        func snap(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            if value - low <= edgeSnapDistance { return low }
            if high - value <= edgeSnapDistance { return high }
            return min(max(value.rounded(), low), high)
        }
        let minX = snap(rect.minX, bounds.minX, bounds.maxX)
        let maxX = max(snap(rect.maxX, bounds.minX, bounds.maxX), minX)
        let minY = snap(rect.minY, bounds.minY, bounds.maxY)
        let maxY = max(snap(rect.maxY, bounds.minY, bounds.maxY), minY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
