//
//  TimeoutCache.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class TimeoutCache<Key: Hashable, Value> {
    private let timeout: UInt64
    private var head: Entry?
    private var tail: Entry?
    private var cache = [Key: Entry]()
    private var purgeRestrictionExpirationTimestamp: UInt64 = 0
    private var purgeRestrictionExpired: Bool { DispatchTime.now().uptimeMilliseconds > purgeRestrictionExpirationTimestamp }
    
    init(timeout: UInt64) {
        self.timeout = timeout
    }
    
    subscript(key: Key) -> Value? {
        get {
            guard let entry = cache[key], !entry.expired else {
                remove(key)
                return nil
            }
            return entry.value
        }
        set {
            remove(key)
            purge()
            guard let value = newValue else { return }
            let expirationTimestamp = DispatchTime.now().uptimeMilliseconds + timeout
            let entry = Entry(key: key, value: value, expirationTimestamp: expirationTimestamp, previous: tail)
            entry.previous?.next = entry
            if head == nil { head = entry }
            tail = entry
            cache[key] = entry
        }
    }
    
    private func remove(_ key: Key) {
        guard let entry = cache[key] else { return }
        cache[key] = nil
        if entry === tail { tail = entry.previous }
        if entry === head { head = entry.next }
        entry.previous?.next = entry.next
        entry.next?.previous = entry.previous
    }
    
    private func purge() {
        guard purgeRestrictionExpired else { return }
        var entry = head
        while entry != nil && entry!.expired {
            remove(entry!.key)
            entry = entry!.next
        }
        purgeRestrictionExpirationTimestamp = DispatchTime.now().uptimeMilliseconds + (100 * timeout)
    }
    
    private class Entry {
        let key: Key
        let value: Value
        let expirationTimestamp: UInt64
        var previous: Entry?
        var next: Entry?
        var expired: Bool { DispatchTime.now().uptimeMilliseconds > expirationTimestamp }
        
        init(key: Key, value: Value, expirationTimestamp: UInt64, previous: Entry?) {
            self.key = key
            self.value = value
            self.expirationTimestamp = expirationTimestamp
            self.previous = previous
        }
    }
}
