/// GreenButtonManager.swift

import Cocoa

class GreenButtonManager {
    private var eventMonitor: ActiveEventMonitor!
    private var windowElement: AccessibilityElement?
    private var buttonFrame: CGRect?

    init() {
        eventMonitor = ActiveEventMonitor(mask: [.leftMouseDown, .leftMouseUp], filterer: filter, handler: { _ in })
        toggleListening()
        Notification.Name.greenButtonOverride.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }

    private func toggleListening() {
        if Defaults.greenButtonOverride.enabled {
            if !eventMonitor.running {
                eventMonitor.start()
            }
        } else {
            eventMonitor.stop()
        }
    }

    /// Runs on the event tap thread. Returning true consumes the event so the
    /// app never sees the click that would put its window into native full screen.
    private func filter(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                let location = event.cgEvent?.location,
                let element = AccessibilityElement(location),
                element.isFullScreenButton == true,
                case let buttonFrame = element.frame,
                buttonFrame != .null,
                let windowElement = element.windowElement
            else {
                return false
            }
            self.windowElement = windowElement
            self.buttonFrame = buttonFrame
            return true
        case .leftMouseUp:
            guard let windowElement = windowElement, let buttonFrame = buttonFrame else {
                return false
            }
            self.windowElement = nil
            self.buttonFrame = nil
            // Releasing outside the button cancels the click, matching native button behavior
            if let location = event.cgEvent?.location, buttonFrame.contains(location) {
                DispatchQueue.main.async {
                    GreenButtonManager.executeAction(windowElement)
                }
            }
            return true
        default:
            return false
        }
    }

    private static func executeAction(_ windowElement: AccessibilityElement) {
        if let windowId = windowElement.getWindowId(),
           case let windowFrame = windowElement.frame,
           windowFrame != .null,
           let historyAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
           historyAction.action == .maximize,
           historyAction.rect == windowFrame {
            WindowAction.restore.postTitleBar(windowElement: windowElement)
            return
        }
        WindowAction.maximize.postTitleBar(windowElement: windowElement)
    }
}
