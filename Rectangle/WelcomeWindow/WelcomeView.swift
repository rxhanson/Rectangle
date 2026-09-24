/// WelcomeView.swift

import SwiftUI
import AppKit

struct WelcomeView: View {
    private static var windowController: NSWindowController?
    private static var windowDelegate: WelcomeWindowDelegate?

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Rectangle!")
                .font(.largeTitle)
                .bold()
            
            Text("Please select your default shortcuts and behavior")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Equal sized buttons
            VStack(spacing: 10) {
                Button(action: {
                    finishSelection(usingRecommended: true)
                }) {
                    HStack(spacing: 6) {
                        Image("StatusTemplate")
                            .renderingMode(.template)
                        Text("Recommended")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 200, height: 38)
                
                Button(action: {
                    finishSelection(usingRecommended: false)
                }) {
                    Text("Spectacle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(width: 200, height: 38)
            }
            .padding(.vertical, 8)
            
            // Explanatory Text with Multi-line Wrapping
            VStack(spacing: 8) {
                Text("Spectacle shortcuts are more likely to conflict with other shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Choosing Spectacle will also cycle 1/2, 2/3, and 1/3 window widths on repeated shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - Presentation & Lifecycle
    
    static func show() {
        guard windowController == nil, !Defaults.wasWelcomeDisplayed.enabled else { return }
        
        Defaults.wasWelcomeDisplayed.enabled = true

        let hostingController = NSHostingController(rootView: WelcomeView())
        let window = NSWindow(contentViewController: hostingController)
        
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()

        let delegate = WelcomeWindowDelegate()
        window.delegate = delegate
        windowDelegate = delegate

        let controller = NSWindowController(window: window)
        windowController = controller
        
        NSApp.activate(ignoringOtherApps: true)
        
        let response = NSApp.runModal(for: window)
        
        let usingRecommended = (response == .alertFirstButtonReturn || response == .abort || response == .stop)
        applyDefaults(usingRecommended: usingRecommended)
        
        window.delegate = nil
        windowController?.close()
        windowController = nil
        windowDelegate = nil
    }

    private func finishSelection(usingRecommended: Bool) {
        Self.applyDefaults(usingRecommended: usingRecommended)
        
        let code: NSApplication.ModalResponse = usingRecommended ? .alertFirstButtonReturn : .alertSecondButtonReturn
        NSApp.stopModal(withCode: code)
    }

    private static func applyDefaults(usingRecommended: Bool) {
        Defaults.alternateDefaultShortcuts.enabled = usingRecommended
        Defaults.subsequentExecutionMode.value = usingRecommended ? .acrossMonitor : .resize
    }
}

// MARK: - Window Delegate

private class WelcomeWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if NSApp.modalWindow != nil {
            NSApp.stopModal(withCode: .abort)
        }
    }
}
