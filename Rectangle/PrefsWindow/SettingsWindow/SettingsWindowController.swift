/// SettingsWindowController.swift

import AppKit

class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let contentViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: contentViewController)
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = SettingsTabViewController.Tab.shortcuts.label
        window.setContentSize(SettingsTabViewController.Tab.shortcuts.defaultSize)
        window.minSize = NSSize(width: 420, height: 350)
        window.center()
        
        self.init(window: window)
    }
}

class SettingsTabViewController: NSTabViewController {
    
    enum Tab: Int, CaseIterable {
        case shortcuts
        case snapAreas
        case behavior
        case appSettings
        
        var label: String {
            switch self {
            case .shortcuts:   return "Shortcuts"
            case .snapAreas:   return "Snap Areas"
            case .behavior:    return "Behavior"
            case .appSettings: return "App Settings"
            }
        }
        
        var imageName: String {
            switch self {
            case .shortcuts:   return "keyboardToolbarTemplate"
            case .snapAreas:   return "snapAreaTemplate"
            case .behavior:    return "toolbarSettingsTemplate"
            case .appSettings: return "appSettingsTemplate"
            }
        }
        
        var defaultSize: NSSize {
            switch self {
            case .shortcuts:   return NSSize(width: 500, height: 540)
            case .snapAreas:   return NSScreen.portraitDisplayConnected
                ? NSSize(width: 500, height: 860)
                : NSSize(width: 500, height: 616)
            case .behavior:    return NSSize(width: 500, height: 550)
            case .appSettings: return NSSize(width: 500, height: 442)
            }
        }
        
        func makeViewController() -> NSViewController {
            switch self {
            case .shortcuts:
                return ShortcutsViewController()
            case .snapAreas:
                return SnapAreaSettingsViewController()
            case .behavior:
                return BehaviorSettingsViewController()
            case .appSettings:
                return AppSettingsViewController()
            }
        }
    }
    
    private var savedTabSizes: [Int: NSSize] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tabStyle = .toolbar
        
        for tab in Tab.allCases {
            let item = NSTabViewItem(viewController: tab.makeViewController())
            item.label = tab.label
            item.image = NSImage(imageLiteralResourceName: tab.imageName)
            addTabViewItem(item)
        }
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
        
        if let savedSize = savedTabSizes[index] {
            resizeWindow(to: savedSize, animated: true)
        } else if Tab.allCases.indices.contains(index) {
            let initialSize = Tab.allCases[index].defaultSize
            resizeWindow(to: initialSize, animated: true)
        }
    }
}
