/// SettingsWindowController.swift

import AppKit

class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let contentViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: contentViewController)
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Shortcuts"
        window.setContentSize(NSSize(width: 480, height: 540))
        window.minSize = NSSize(width: 420, height: 350)
        window.center()
        
        self.init(window: window)
    }
}

class SettingsTabViewController: NSTabViewController {
    
    private var savedTabSizes: [Int: NSSize] = [:]
    
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

        let behaviorVC = BehaviorSettingsViewController()
        let behaviorItem = NSTabViewItem(viewController: behaviorVC)
        behaviorItem.label = "Behavior"
        behaviorItem.image = NSImage(imageLiteralResourceName: "toolbarSettingsTemplate")
        addTabViewItem(behaviorItem)
        
        let appSettingsVC = AppSettingsViewController()
        let appSettingsItem = NSTabViewItem(viewController: appSettingsVC)
        appSettingsItem.label = "App Settings"
        appSettingsItem.image = NSImage(imageLiteralResourceName: "toolbarSettingsTemplate")
        addTabViewItem(appSettingsItem)
    }
    
    override var selectedTabViewItemIndex: Int {
        willSet {
            if selectedTabViewItemIndex != -1, let window = view.window {
                savedTabSizes[selectedTabViewItemIndex] = window.frame.size
            }
        }
        didSet {
            guard selectedTabViewItemIndex != -1 else { return }
            let selectedItem = tabViewItems[selectedTabViewItemIndex]
            tabDidSwitch(to: selectedItem, at: selectedTabViewItemIndex)
        }
    }
    
    private func resizeWindow(to newSize: NSSize, animated: Bool) {
        guard let window = view.window else { return }
        
        var frame = window.frame
        frame.origin.y -= (newSize.height - frame.size.height)
        frame.size = newSize
        
        window.setFrame(frame, display: true, animate: animated)
    }
    
    private func tabDidSwitch(to item: NSTabViewItem, at index: Int) {
        view.window?.title = item.label
        
        if let savedSize = savedTabSizes[selectedTabViewItemIndex] {
            resizeWindow(to: savedSize, animated: true)
        }
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
