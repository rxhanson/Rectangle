/// SettingsWindowController.swift

import AppKit

class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let contentViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: contentViewController)
        
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Preferences"
        window.center()
        
        self.init(window: window)
    }
}

class SettingsTabViewController: NSTabViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configures the tab view controller to display tabs inside the window's toolbar
        self.tabStyle = .toolbar
        
        // 1. General Settings View Controller
        let generalVC = GeneralSettingsViewController()
        let generalItem = NSTabViewItem(viewController: generalVC)
        generalItem.label = "General"
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        addTabViewItem(generalItem)
        
        // 2. Advanced Settings View Controller
        let advancedVC = AdvancedSettingsViewController()
        let advancedItem = NSTabViewItem(viewController: advancedVC)
        advancedItem.label = "Advanced"
        advancedItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Advanced")
        addTabViewItem(advancedItem)
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
