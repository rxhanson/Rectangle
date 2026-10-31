/// WindowUtil.swift

import Foundation

class WindowUtil {
    private static var windowListCache = TimeoutCache<[CGWindowID]?, [WindowInfo]>(timeout: 100)

    /// Drag tracking needs current geometry rather than the window list's 100 ms cache.
    static func getWindowFrame(id: CGWindowID) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let info = infos.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              !frame.isNull, !frame.isEmpty else { return nil }
        return frame
    }
    
    static func getWindowList(ids: [CGWindowID]? = nil, all: Bool = false, forceRefresh: Bool = false) -> [WindowInfo] {
        if !forceRefresh, let infos = windowListCache[ids] {
            return infos
        }
        var infos = [WindowInfo]()
        var rawInfos: CFArray?
        if let ids {
            let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: ids.count)
            defer { values.deallocate() }
            for (i, id) in ids.enumerated() {
                values[i] = UnsafeRawPointer(bitPattern: UInt(id))
            }
            let rawIds = CFArrayCreate(kCFAllocatorDefault, values, ids.count, nil)
            rawInfos = CGWindowListCreateDescriptionFromArray(rawIds)
        } else {
            rawInfos = CGWindowListCopyWindowInfo([all ? .optionAll : .optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        }
        if let rawInfos {
            let count = rawInfos.getCount()
            for i in 0..<count {
                let rawInfo = rawInfos.getValue(i) as CFDictionary
                let rawId = rawInfo.getValue(kCGWindowNumber) as CFNumber
                let rawLevel = rawInfo.getValue(kCGWindowLayer) as CFNumber
                let rawFrame = rawInfo.getValue(kCGWindowBounds) as CFDictionary
                let rawPid = rawInfo.getValue(kCGWindowOwnerPID) as CFNumber
                let rawProcessName = rawInfo.getValue(kCGWindowOwnerName) as CFString?
                let id = CGWindowID(truncating: rawId)
                let level = CGWindowLevel(truncating: rawLevel)
                guard let frame = CGRect(dictionaryRepresentation: rawFrame) else {
                    continue
                }
                let pid = pid_t(truncating: rawPid)
                var processName: String?
                if let rawProcessName {
                    processName = String(rawProcessName)
                }
                let alpha = (rawInfo.getValue(kCGWindowAlpha) as CFNumber?).map { CGFloat(truncating: $0) } ?? 1
                let info = WindowInfo(id: id, level: level, frame: frame, pid: pid, processName: processName, alpha: alpha)
                infos.append(info)
            }
        }
        windowListCache[ids] = infos
        return infos
    }

    /// AX position/size can momentarily lag the window server right after a window is
    /// dragged to another display, still reporting it on the display it came from. The
    /// window server tracks the move live, so when the two frames disagree, prefer the
    /// server's. Otherwise a keyboard action resolves the stale display and, for one the
    /// window already satisfies there (e.g. Maximize right after it was maximized), it
    /// silently does nothing until the window is clicked and the app flushes its geometry.
    static func reconciledFrame(accessibilityFrame: CGRect, serverFrame: CGRect?, tolerance: CGFloat = 1) -> CGRect {
        guard let serverFrame, !serverFrame.isNull, !serverFrame.isEmpty else { return accessibilityFrame }
        guard !accessibilityFrame.isNull else { return serverFrame }
        let originMatches = abs(accessibilityFrame.minX - serverFrame.minX) <= tolerance
            && abs(accessibilityFrame.minY - serverFrame.minY) <= tolerance
        let sizeMatches = abs(accessibilityFrame.width - serverFrame.width) <= tolerance
            && abs(accessibilityFrame.height - serverFrame.height) <= tolerance
        return originMatches && sizeMatches ? accessibilityFrame : serverFrame
    }

    static func reconciledFrame(accessibilityFrame: CGRect, windowId: CGWindowID?, tolerance: CGFloat = 1) -> CGRect {
        reconciledFrame(accessibilityFrame: accessibilityFrame,
                        serverFrame: windowId.flatMap { getWindowFrame(id: $0) },
                        tolerance: tolerance)
    }
}

struct WindowInfo {
    let id: CGWindowID
    let level: CGWindowLevel
    let frame: CGRect
    let pid: pid_t
    let processName: String?
    var alpha: CGFloat = 1
}
