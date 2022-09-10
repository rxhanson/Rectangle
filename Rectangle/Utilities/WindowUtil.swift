//
//  WindowUtil.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class WindowUtil {
    private static var windowListCache = [[CGWindowID]?: WindowListInfo]()
    private static var nowTimestamp: UInt64 { DispatchTime.now().uptimeNanoseconds / 1_000_000 }
    
    static func windowList(_ ids: [CGWindowID]? = nil) -> [WindowInfo] {
        if let listInfo = windowListCache[ids], nowTimestamp - listInfo.timestamp <= 100 { return listInfo.infos }
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
            array = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        }
        if let array = array {
            let count = CFArrayGetCount(array)
            for i in 0..<count {
                let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(array, i), to: CFDictionary.self)
                let id = dictionaryValue(dictionary, kCGWindowNumber) as CFNumber
                let layer = dictionaryValue(dictionary, kCGWindowLayer) as CFNumber
                let frame = dictionaryValue(dictionary, kCGWindowBounds) as CFDictionary
                let pid = dictionaryValue(dictionary, kCGWindowOwnerPID) as CFNumber
                if let frame = CGRect(dictionaryRepresentation: frame) {
                    let info = WindowInfo(id: id as! CGWindowID, layer: layer as! Int, frame: frame, pid: pid as! pid_t)
                    infos.append(info)
                }
            }
        }
        windowListCache[ids] = WindowListInfo(timestamp: nowTimestamp, infos: infos)
        return infos
    }
    
    private static func dictionaryValue<T>(_ dictionary: CFDictionary, _ key: CFString) -> T {
        return unsafeBitCast(CFDictionaryGetValue(dictionary, unsafeBitCast(key, to: UnsafeRawPointer.self)), to: T.self)
    }
    
    private struct WindowListInfo {
        let timestamp: UInt64
        let infos: [WindowInfo]
    }
}

struct WindowInfo {
    let id: CGWindowID
    let layer: Int
    let frame: CGRect
    let pid: pid_t
    var bundleIdentifier: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
}
