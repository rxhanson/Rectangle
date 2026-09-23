/// PopoverButton.swift

import AppKit

final class PopoverButton: NSButton, NSPopoverDelegate {

    private var popover: NSPopover?

    var contentView: NSView? {
        didSet {
            setupButton()
        }
    }

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
        guard let contentView = contentView else { return }

        let controller = NSViewController()
        controller.view = contentView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
        popover.delegate = self

        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
        popover.animates = false
        self.popover = popover
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        self.popover = nil
    }
}
