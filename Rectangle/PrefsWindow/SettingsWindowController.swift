/// SettingsWindowController.swift

import AppKit

class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let contentViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: contentViewController)
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Preferences"
        window.setContentSize(NSSize(width: 480, height: 540))
        window.minSize = NSSize(width: 420, height: 350)
        window.center()
        
        self.init(window: window)
    }
}

class SettingsTabViewController: NSTabViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tabStyle = .toolbar
        
        let shortcutsVC = ShortcutsViewController()
        let shortcutsItem = NSTabViewItem(viewController: shortcutsVC)
        shortcutsItem.label = "Shortcuts"
        shortcutsItem.image = NSImage(imageLiteralResourceName: "keyboardToolbarTemplate")
        addTabViewItem(shortcutsItem)

        let snapAreaVC = NSViewController.newControllerFromStoryboard(identifier: "SnapAreaViewController")
        let snapAreaItem = NSTabViewItem(viewController: snapAreaVC)
        snapAreaItem.label = "Snap Areas"
        snapAreaItem.image = NSImage(imageLiteralResourceName: "snapAreaTemplate")
        addTabViewItem(snapAreaItem)

        let generalVC = GeneralSettingsViewController()
        let generalItem = NSTabViewItem(viewController: generalVC)
        generalItem.label = "General"
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        addTabViewItem(generalItem)
    }
}

// Example View Controllers
class GeneralSettingsViewController: NSViewController {
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        
        let label = NSTextField(labelWithString: "General Settings View")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

class AdvancedSettingsViewController: NSViewController {
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        
        let label = NSTextField(labelWithString: "Advanced Settings View")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
