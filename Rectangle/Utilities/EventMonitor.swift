/// EventMonitor.swift

import Cocoa

protocol EventMonitor {
    var running: Bool { get }
    
    func start()
    func stop()
}

public class PassiveEventMonitor: EventMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    var running: Bool { localMonitor != nil && globalMonitor != nil }
    
    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            self.handler(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    public func stop() {
        if localMonitor != nil {
            NSEvent.removeMonitor(localMonitor!)
            localMonitor = nil
        }
        if globalMonitor != nil {
            NSEvent.removeMonitor(globalMonitor!)
            globalMonitor = nil
        }
    }
}

public class ActiveEventMonitor: EventMonitor {
    // start(), stop() and the tap's own re-enable can all run at once - the
    // last of those arrives on the tap's thread while the others come from
    // the main thread - so the port and its thread are guarded.
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var thread: RunLoopThread?
    private let mask: NSEvent.EventTypeMask
    public let filterer: (NSEvent) -> Bool
    public let handler: (NSEvent) -> Void

    var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tap != nil
    }

    public init(mask: NSEvent.EventTypeMask, filterer: @escaping (NSEvent) -> Bool, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.filterer = filterer
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard tap == nil else { return }
        // Only a trusted process can create a tap. Failing silently here
        // leaves every consumer of this monitor looking simply broken, with
        // nothing anywhere to say why.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask.rawValue, callback: tapCallback, userInfo: CUtil.bridge(obj: self))
        else {
            Logger.log("Unable to create an event tap - accessibility may no longer be authorized")
            return
        }
        let thread = RunLoopThread(mode: .default, qualityOfService: .userInteractive, start: true)
        thread.runLoop?.add(tap, forMode: .default)
        self.tap = tap
        self.thread = thread
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let tap = tap else { return }
        thread?.runLoop?.remove(tap, forMode: .default)
        thread?.cancel()
        thread = nil
        CGEvent.tapEnable(tap: tap, enable: false)
        // CoreGraphics holds internal references to the CFMachPort from tapCreate, so
        // releasing ours never deallocates it; without an explicit invalidate, the
        // WindowServer keeps the (disabled) tap registration until the process exits.
        // stop()/start() cycles (app switches while snapping is active, and the
        // tapDisabledByTimeout recovery below) would otherwise each leak one entry,
        // degrading system-wide input latency once they accumulate.
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    /// macOS disables a tap whose callback ran long, or on some user input.
    /// Re-enabling the existing port is both the documented remedy and safer
    /// than tearing the monitor down from inside its own callback, which
    /// races any concurrent stop().
    fileprivate func reEnable() {
        lock.lock()
        defer { lock.unlock() }
        guard let tap = tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

fileprivate func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    var filtered = false
    if let ptr = refcon {
        let eventMonitor = CUtil.bridge(ptr: ptr) as ActiveEventMonitor
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            eventMonitor.reEnable()
        } else {
            if let nsEvent = NSEvent(cgEvent: event) {
                filtered = eventMonitor.filterer(nsEvent)
                DispatchQueue.main.async { eventMonitor.handler(nsEvent) }
            }
        }
    }
    return filtered ? nil : Unmanaged.passUnretained(event)
}
