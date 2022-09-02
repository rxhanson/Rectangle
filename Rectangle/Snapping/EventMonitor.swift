//
//  EventMonitor.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/4/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

protocol EventMonitor {
    var running: Bool { get }
    
    func start()
    func stop()
}

public class PassiveEventMonitor: EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    var running: Bool { monitor != nil }
    
    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    public func stop() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }
    }
}

public class ActiveEventMonitor: EventMonitor {
    private var tap: CFMachPort?
    private let mask: NSEvent.EventTypeMask
    public let filterer: (NSEvent) -> Bool
    public let handler: (NSEvent) -> Void

    var running: Bool { tap != nil }
    
    public init(mask: NSEvent.EventTypeMask, filterer: @escaping (NSEvent) -> Bool, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.filterer = filterer
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask.rawValue, callback: tapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap = tap { RunLoop.main.add(tap, forMode: .common) }
    }
    
    public func stop() {
        if let tap = tap {
            RunLoop.main.remove(tap, forMode: .common)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
    }
}

fileprivate func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    var filtered = false
    if let ptr = refcon {
        let eventMonitor = Unmanaged<ActiveEventMonitor>.fromOpaque(ptr).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            eventMonitor.stop()
            eventMonitor.start()
        } else {
            if let nsEvent = NSEvent(cgEvent: event) {
                filtered = eventMonitor.filterer(nsEvent)
                DispatchQueue.main.async { eventMonitor.handler(nsEvent) }
            }
        }
    }
    return filtered ? nil : Unmanaged.passUnretained(event)
}
