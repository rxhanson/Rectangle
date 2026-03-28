//
//  WindowFingerprint.swift
//  Rectangle
//
//  Created by Rectangle contributors.
//

import Cocoa

struct WindowFingerprint: Codable, Hashable {
    let bundleID: String
    let windowIndex: Int
    let windowTitleHash: Int?

    static func from(windowElement: AccessibilityElement, pid: pid_t) -> WindowFingerprint? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else { return nil }

        let appElement = AccessibilityElement(pid)
        let allWindows = appElement.windowElements ?? []
        let windowIndex = allWindows.firstIndex(where: { $0.getWindowId() == windowElement.getWindowId() }) ?? 0
        let titleHash = windowElement.title?.hashValue

        return WindowFingerprint(bundleID: bundleID, windowIndex: windowIndex, windowTitleHash: titleHash)
    }

    func matches(_ other: WindowFingerprint) -> Bool {
        guard bundleID == other.bundleID else { return false }
        if let myHash = windowTitleHash, let otherHash = other.windowTitleHash, myHash == otherHash {
            return true
        }
        return windowIndex == other.windowIndex
    }
}

struct SavedWindowPosition: Codable {
    let fingerprint: WindowFingerprint
    let rect: CodableRect
    let actionRawValue: Int?
    let displayUUID: String
}

struct CodableRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct PinnedPosition: Codable {
    let actionRawValue: Int
    let displayUUID: String?
}
