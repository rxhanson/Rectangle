/// GreenButtonManager.swift

import Cocoa

enum GreenButtonMode: Int, CaseIterable {
    case off = 0
    case builtIn = 1
    case rectangle = 2
}

class GreenButtonManager {
    
    private static let syntheticEventMarker: Int64 = 0x5245_4354

    private var eventMonitor: ActiveEventMonitor!
    private var windowElement: AccessibilityElement?
    private var buttonFrame: CGRect?
    private var heldOption = false
    private var heldCommand = false

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
        if Defaults.greenButtonMode.value != .off {
            if !eventMonitor.running {
                eventMonitor.start()
            }
        } else {
            eventMonitor.stop()
        }
    }

    private enum ClickAction {
        case rectangleMaximize
        case nativeFill
        case fullScreen
    }


    private func filter(_ event: NSEvent) -> Bool {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return false
        }
        switch event.type {
        case .leftMouseDown:
            guard
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
            heldOption = event.modifierFlags.contains(.option)
            heldCommand = event.modifierFlags.contains(.command)
            return true
        case .leftMouseUp:
            guard let windowElement = windowElement, let buttonFrame = buttonFrame else {
                return false
            }
            let action = GreenButtonManager.resolveAction(mode: Defaults.greenButtonMode.value, optionHeld: heldOption, commandHeld: heldCommand)
            self.windowElement = nil
            self.buttonFrame = nil
            
            if let location = event.cgEvent?.location, buttonFrame.contains(location) {
                DispatchQueue.main.async {
                    GreenButtonManager.perform(action, windowElement: windowElement, buttonFrame: buttonFrame)
                }
            }
            return true
        default:
            return false
        }
    }


    private static func resolveAction(mode: GreenButtonMode, optionHeld: Bool, commandHeld: Bool) -> ClickAction {
        if commandHeld {
            return .fullScreen
        }
        let plainClickIsNativeFill = mode == .builtIn
        if optionHeld {
            return plainClickIsNativeFill ? .rectangleMaximize : .nativeFill
        }
        return plainClickIsNativeFill ? .nativeFill : .rectangleMaximize
    }

    private static func perform(_ action: ClickAction, windowElement: AccessibilityElement, buttonFrame: CGRect) {
        switch action {
        case .rectangleMaximize:
            executeRectangleMaximize(windowElement)
        case .nativeFill:
            postNativeClick(at: CGPoint(x: buttonFrame.midX, y: buttonFrame.midY), flags: .maskAlternate)
        case .fullScreen:
            postNativeClick(at: CGPoint(x: buttonFrame.midX, y: buttonFrame.midY), flags: [])
        }
    }

    private static func executeRectangleMaximize(_ windowElement: AccessibilityElement) {
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

    private static func postNativeClick(at point: CGPoint, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
            guard let cgEvent = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
                continue
            }
            cgEvent.flags = flags
            cgEvent.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            cgEvent.post(tap: .cgSessionEventTap)
        }
    }
}
