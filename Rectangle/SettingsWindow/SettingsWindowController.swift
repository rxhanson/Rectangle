/// SettingsWindowController.swift

import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    
    var onClose: (() -> Void)?
    
    convenience init() {
        let contentViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: contentViewController)
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        
        let initialTab = SettingsTabViewController.currentTab
        window.title = initialTab.label
        let minSize = NSSize(width: 500, height: 350)
        if let savedWindowSize = initialTab.savedWindowSize {
            contentViewController.resizeWindow(toFrameSize: savedWindowSize, animated: false)
        } else {
            let initialSize = initialTab.defaultSize
            ?? contentViewController.tabViewItems[initialTab.rawValue].viewController?.view.fittingSize
            ?? minSize
            window.setContentSize(initialSize)
        }
        window.minSize = minSize
        window.center()
        
        self.init(window: window)
        window.delegate = self
    }
    
    func windowWillClose(_ notification: Notification) {
        (contentViewController as? SettingsTabViewController)?.saveCurrentSize()
        onClose?()
        DispatchQueue.main.async { self.window?.contentViewController = nil }
    }
}

class SettingsTabViewController: NSTabViewController {
    static var currentTab: Tab = .shortcuts
    static var savedWindowSizes: [Int: NSSize] = [:]
    
    enum Tab: Int, CaseIterable {
        case shortcuts
        case snapAreas
        case behavior
        case appSettings
        
        var label: String {
            switch self {
            case .shortcuts:   return String(localized:"Shortcuts")
            case .snapAreas:   return String(localized:"Snap Areas")
            case .behavior:    return String(localized:"Behavior")
            case .appSettings: return String(localized:"App Settings")
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
        
        var savedWindowSize: NSSize? {
            SettingsTabViewController.savedWindowSizes[rawValue]
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tabStyle = .toolbar
        
        for tab in Tab.allCases {
            let item = NSTabViewItem(viewController: tab.makeViewController())
            item.label = tab.label
            item.image = NSImage(imageLiteralResourceName: tab.imageName)
            addTabViewItem(item)
        }
        selectedTabViewItemIndex = SettingsTabViewController.currentTab.rawValue
        
        Notification.Name.snapAreaSettingsNeedsResize.onPost {[weak self] notification in
            guard let self,
                  let snapAreasIndex = Tab.allCases.firstIndex(of: .snapAreas)
            else { return }

            Self.savedWindowSizes.removeValue(forKey: snapAreasIndex)
            
            if selectedTabViewItemIndex == snapAreasIndex {
                let viewController = tabViewItems[snapAreasIndex].viewController!
                
                viewController.view.layoutSubtreeIfNeeded()
                
                DispatchQueue.main.async {
                    let dynamicSize = self.calculateContentSize(for: viewController)
                    self.resizeWindow(toContentSize: dynamicSize, animated: true)
                }
            }
        }
    }
    
    override var selectedTabViewItemIndex: Int {
        willSet {
            if selectedTabViewItemIndex != -1, let window = view.window {
                Self.savedWindowSizes[selectedTabViewItemIndex] = window.frame.size
            }
        }
        didSet {
            guard selectedTabViewItemIndex != -1 else { return }
            let selectedItem = tabViewItems[selectedTabViewItemIndex]
            tabDidSwitch(to: selectedItem, at: selectedTabViewItemIndex)
        }
    }
    
    func saveCurrentSize() {
        if let window = view.window {
            Self.savedWindowSizes[Self.currentTab.rawValue] = window.frame.size
        }
    }
    
    private func tabDidSwitch(to item: NSTabViewItem, at index: Int) {
        guard let window = view.window, let viewController = item.viewController else { return }
        
        if let tab = Tab(rawValue: index) {
            SettingsTabViewController.currentTab = tab
        }
        window.title = item.label
        
        if let savedSize = Self.savedWindowSizes[index] {
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
    
    func resizeWindow(toFrameSize targetFrameSize: NSSize, animated: Bool) {
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
