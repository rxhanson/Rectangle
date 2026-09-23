/// SettingsWindowController.swift

import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let contentViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: contentViewController)
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = SettingsTabViewController.Tab.shortcuts.label
        
        let initialTab = SettingsTabViewController.Tab.shortcuts
        let initialSize = initialTab.defaultSize ?? initialTab.makeViewController().view.fittingSize
        window.setContentSize(initialSize)
        window.minSize = NSSize(width: 500, height: 350)
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
        
        var defaultSize: NSSize? {
            switch self {
            case .shortcuts:   return NSSize(width: 500, height: 540)
            default: return nil
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
    
    private func tabDidSwitch(to item: NSTabViewItem, at index: Int) {
        guard let window = view.window, let viewController = item.viewController else { return }
        
        window.title = item.label
        
        if let savedSize = savedTabSizes[index] {
            resizeWindow(toFrameSize: savedSize, animated: true)
        } else if Tab.allCases.indices.contains(index) {
            let tab = Tab.allCases[index]
            
            if let explicitSize = tab.defaultSize {
                resizeWindow(toContentSize: explicitSize, animated: true)
            } else {
                let dynamicSize = calculateContentSize(for: viewController)
                resizeWindow(toContentSize: dynamicSize, animated: true)
            }
        }
    }
    
    private func calculateContentSize(for vc: NSViewController) -> NSSize {
        _ = vc.view // Ensure the view hierarchy is loaded
        
        if vc.preferredContentSize != .zero {
            return vc.preferredContentSize
        }
        
        let fitting = vc.view.fittingSize
        if fitting != .zero {
            return fitting
        }
        
        return vc.view.bounds.size
    }
    
    private func resizeWindow(toFrameSize targetFrameSize: NSSize, animated: Bool) {
        guard let window = view.window else { return }
        
        var frame = window.frame
        frame.origin.y -= (targetFrameSize.height - frame.size.height)
        frame.size = targetFrameSize
        
        window.setFrame(frame, display: true, animate: animated)
    }
    
    private func resizeWindow(toContentSize contentSize: NSSize, animated: Bool) {
        guard let window = view.window else { return }
        
        // Convert inner content size to total window frame rect (accounting for title bar and toolbar)
        let targetFrameRect = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        resizeWindow(toFrameSize: targetFrameRect.size, animated: animated)
    }
}
