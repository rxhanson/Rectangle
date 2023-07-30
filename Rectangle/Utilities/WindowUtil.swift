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
        if let infos = windowListCache[ids] { return infos }
        var infos = [WindowInfo]()
        var array: CFArray?
        if let ids = ids {
            let ptr = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: ids.count)
            for i in 0..<ids.count {
                ptr[i] = UnsafeRawPointer(bitPattern: UInt(ids[i]))
            }
            let ids = CFArrayCreate(kCFAllocatorDefault, ptr, ids.count, nil)
            array = CGWindowListCreateDescriptionFromArray(ids)
        } else {
            array = CGWindowListCopyWindowInfo([all ? .optionAll : .optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        }
        if let array = array {
            let count = array.getCount()
            for i in 0..<count {
                let dictionary = array.getValue(i) as CFDictionary
                let id = dictionary.getValue(kCGWindowNumber) as CFNumber
                let frame = (dictionary.getValue(kCGWindowBounds) as CFDictionary).toRect()
                let pid = dictionary.getValue(kCGWindowOwnerPID) as CFNumber
                let processName = dictionary.getValue(kCGWindowOwnerName) as CFString
                if let frame = frame {
                    let info = WindowInfo(id: CGWindowID(truncating: id), frame: frame, pid: pid_t(truncating: pid), processName: String(processName))
                    infos.append(info)
                }
            }
        }
        windowListCache[ids] = infos
        return infos
    }
}

struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect
    let pid: pid_t
    let processName: String
}
