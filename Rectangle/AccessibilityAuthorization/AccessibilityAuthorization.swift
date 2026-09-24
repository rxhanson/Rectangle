/// AccessibilityAuthorization.swift

import Foundation
import SwiftUI

class AccessibilityAuthorization: ObservableObject {
    
    private var windowController: NSWindowController?
    private var timer: Timer?
    
    @discardableResult
    public func checkAccessibility(completion: @escaping () -> Void) -> Bool {
        if !AXIsProcessTrusted() {
            showWindow(completion: completion)
            startPolling(completion: completion)
            return false
        } else {
            return true
        }
    }
    
    private func showWindow(completion: @escaping () -> Void) {
        if windowController == nil {
            let rootView = AccessibilityView(manager: self)
            let hostingController = NSHostingController(rootView: rootView)
            
            let window = CustomAccessibilityWindow(
                contentViewController: hostingController
            )
            
            let wc = NSWindowController(window: window)
            self.windowController = wc
        }
        
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            self.windowController?.window?.center()
            self.windowController?.showWindow(self)
        }
    }
    
    private func startPolling(completion: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] t in
            guard let self = self else { return }
            
            if AXIsProcessTrusted() {
                t.invalidate()
                self.timer = nil
                self.closeWindow()
                completion()
            }
        }
    }
    
    func showAuthorizationWindow() {
        if windowController?.window?.isMiniaturized == true {
            windowController?.window?.deminiaturize(self)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func closeWindow() {
        windowController?.close()
        windowController = nil
    }
}

// MARK: - Window Handling Termination on Close

private class CustomAccessibilityWindow: NSWindow {
    
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.contentViewController = contentViewController
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        
        let closeButton = self.standardWindowButton(.closeButton)
        closeButton?.target = self
        closeButton?.action = #selector(closeButtonClicked)
    }
    
    @objc private func closeButtonClicked() {
        exit(1)
    }
}
