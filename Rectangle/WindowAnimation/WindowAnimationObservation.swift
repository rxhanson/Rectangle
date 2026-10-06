import Cocoa
import QuartzCore

/// Notifications only schedule readback; they do not prove a frame was displayed.
final class WindowAnimationObservation {
    private var observer: AXObserver?
    private let request: WindowAnimationRequest
    init(pid: pid_t, element: AXUIElement, request: WindowAnimationRequest) {
        self.request = request
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else { return }
            Unmanaged<WindowAnimationRequest>.fromOpaque(context).takeUnretainedValue()
                .geometryChanged(resized: notification as String == kAXResizedNotification)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let context = Unmanaged.passUnretained(request).toOpaque()
        for notification in [kAXMovedNotification, kAXResizedNotification] {
            _ = AXObserverAddNotification(observer, element, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}
