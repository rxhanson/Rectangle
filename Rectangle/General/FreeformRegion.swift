/// FreeformRegion.swift

import CoreGraphics
import Foundation

/// The area a Freeform preset moves windows to.
///
/// It is stored relative to the usable area (AppKit coordinates) of the display it was selected
/// on, so it keeps its proportions when the resolution, the Dock or the display arrangement changes.
struct FreeformRegion: Codable, Equatable {
    /// The display the area was selected on, if it could be identified.
    let displayID: UUID?
    /// The area as fractions of the work area's size, measured from its bottom-left corner.
    let relativeRect: CGRect

    init?(rect: CGRect, in workArea: CGRect, displayID: UUID?) {
        guard Self.isUsable(workArea), Self.isUsable(rect), workArea.contains(rect) else { return nil }
        self.displayID = displayID
        relativeRect = CGRect(x: (rect.minX - workArea.minX) / workArea.width,
                              y: (rect.minY - workArea.minY) / workArea.height,
                              width: rect.width / workArea.width,
                              height: rect.height / workArea.height)
    }

    /// The area within `workArea`, with its edges on whole points, or nil if it can't be used.
    func rect(in workArea: CGRect) -> CGRect? {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard Self.isUsable(workArea), Self.isUsable(relativeRect), unit.contains(relativeRect) else { return nil }
        let minX = (workArea.minX + relativeRect.minX * workArea.width).rounded()
        let minY = (workArea.minY + relativeRect.minY * workArea.height).rounded()
        let maxX = (workArea.minX + relativeRect.maxX * workArea.width).rounded()
        let maxY = (workArea.minY + relativeRect.maxY * workArea.height).rounded()
        let clipped = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(workArea)
        return Self.isUsable(clipped) ? clipped : nil
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.size.width > 0 && rect.size.height > 0
            && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }
}
