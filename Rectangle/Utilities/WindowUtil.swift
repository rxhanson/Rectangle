//
//  WindowUtil.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class WindowUtil {
    private static var windowListCache = TimeoutCache<[CGWindowID]?, [WindowInfo]>(timeout: 100)
    
    static func getWindowList(ids: [CGWindowID]? = nil, all: Bool = false) -> [WindowInfo] {
        if let infos = windowListCache[ids] {
            return infos
        }
        var infos = [WindowInfo]()
        var rawInfos: CFArray?
        if let ids {
            let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: ids.count)
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
                let info = WindowInfo(id: id, level: level, frame: frame, pid: pid, processName: processName)
                infos.append(info)
            }
        }
        windowListCache[ids] = infos
        return infos
    }
}

struct WindowInfo {
    let id: CGWindowID
    let level: CGWindowLevel
    let frame: CGRect
    let pid: pid_t
    let processName: String?
}
