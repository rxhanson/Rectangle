import AppKit
import SwiftUI

/// An NSButton subclass that manages displaying a SwiftUI view inside an NSPopover when clicked.
final class PopoverButton<Content: View>: NSButton, NSPopoverDelegate {

    private var popover: NSPopover?
    private let rootView: Content

    // MARK: - Initializer

    init(title: String = "", image: NSImage? = nil, rootView: Content) {
        self.rootView = rootView
        super.init(frame: .zero)

        self.title = title
        if let image = image {
            self.image = image
        }
        
        setupButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupButton() {
        target = self
        action = #selector(togglePopover(_:))
    }

    // MARK: - Popover Management

    @objc private func togglePopover(_ sender: Any?) {
        if let popover = popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: rootView)
        popover.delegate = self
        
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        self.popover = popover
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        self.popover = nil
    }
}
