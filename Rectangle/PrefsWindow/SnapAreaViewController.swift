//
//  SnapAreaViewController.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/13/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Cocoa

class SnapAreaViewController: NSViewController {
    
    @IBOutlet weak var windowSnappingCheckbox: NSButton!
    @IBOutlet weak var unsnapRestoreButton: NSButton!
    @IBOutlet weak var animateFootprintCheckbox: NSButton!
    @IBOutlet weak var missionControlDraggingCheckbox: NSButton!

    @IBOutlet weak var topLeftLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var topLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var topRightLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var leftLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var rightLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var bottomLeftLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var bottomLandscapeSelect: NSPopUpButton!
    @IBOutlet weak var bottomRightLandscapeSelect: NSPopUpButton!
    
    @IBOutlet weak var portraitStackView: NSStackView!
    
    @IBOutlet weak var topLeftPortraitSelect: NSPopUpButton!
    @IBOutlet weak var topPortraitSelect: NSPopUpButton!
    @IBOutlet weak var topRightPortraitSelect: NSPopUpButton!
    @IBOutlet weak var leftPortraitSelect: NSPopUpButton!
    @IBOutlet weak var rightPortraitSelect: NSPopUpButton!
    @IBOutlet weak var bottomLeftPortraitSelect: NSPopUpButton!
    @IBOutlet weak var bottomPortraitSelect: NSPopUpButton!
    @IBOutlet weak var bottomRightPortraitSelect: NSPopUpButton!
    
    @IBAction func toggleWindowSnapping(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.windowSnapping.enabled = newSetting
        Notification.Name.windowSnapping.post(object: newSetting)
    }
    
    @IBAction func toggleUnsnapRestore(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.unsnapRestore.enabled = newSetting
    }
    
    @IBAction func toggleAnimateFootprint(_ sender: NSButton) {
        let newSetting: Float = sender.state == .on ? 0.75 : 0
        Defaults.footprintAnimationDurationMultiplier.value = newSetting
    }
    
    @IBAction func toggleMissionControlDragging(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .off
        Defaults.missionControlDragging.enabled = newSetting
        Notification.Name.missionControlDragging.post(object: newSetting)
    }
    
    @IBAction func setLandscapeSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .landscape)
    }

    @IBAction func setPortraitSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .portrait)
    }
    
    private func setSnapArea(sender: NSPopUpButton, type: DisplayOrientation) {
        guard let directional = Directional(rawValue: sender.tag) else { return }
        let selectedTag = sender.selectedTag()
        var snapAreaConfig: SnapAreaConfig?
        if selectedTag < -1, let compound = CompoundSnapArea(rawValue: selectedTag) {
           snapAreaConfig = SnapAreaConfig(compound: compound)
        } else if selectedTag > -1, let action = WindowAction(rawValue: selectedTag) {
            snapAreaConfig = SnapAreaConfig(action: action)
        }
        SnapAreaModel.instance.setConfig(type: type, directional: directional, snapAreaConfig: snapAreaConfig)
    }
    
    override func viewDidLoad() {
        windowSnappingCheckbox.state = Defaults.windowSnapping.userDisabled ? .off : .on
        unsnapRestoreButton.state = Defaults.unsnapRestore.userDisabled ? .off : .on
        animateFootprintCheckbox.state = Defaults.footprintAnimationDurationMultiplier.value > 0 ? .on : .off
        missionControlDraggingCheckbox.state = Defaults.missionControlDragging.userDisabled ? .on : .off
        missionControlDraggingCheckbox.isHidden = !Defaults.missionControlDragging.userDisabled
        loadSnapAreas()
        showHidePortrait()
        
        Notification.Name.configImported.onPost(using: {_ in
            self.loadSnapAreas()
        })
        Notification.Name.appWillBecomeActive.onPost() { _ in
            self.showHidePortrait()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { _ in
            self.showHidePortrait()
        }
    }
    
    func showHidePortrait() {
        let hasPortraitDisplay = NSScreen.screens.contains(where: {!$0.frame.isLandscape})
        portraitStackView.isHidden = !hasPortraitDisplay
    }
    
    func loadSnapAreas() {

        let landscapeSelects: [NSPopUpButton] = [
            topLeftLandscapeSelect,
            topLandscapeSelect,
            topRightLandscapeSelect,
            leftLandscapeSelect,
            rightLandscapeSelect,
            bottomLeftLandscapeSelect,
            bottomLandscapeSelect,
            bottomRightLandscapeSelect
        ]

        let portraitSelects: [NSPopUpButton] = [
            topLeftPortraitSelect,
            topPortraitSelect,
            topRightPortraitSelect,
            leftPortraitSelect,
            rightPortraitSelect,
            bottomLeftPortraitSelect,
            bottomPortraitSelect,
            bottomRightPortraitSelect
        ]
        
        landscapeSelects.forEach { self.configure(select: $0, orientation: .landscape)}
        portraitSelects.forEach { self.configure(select: $0, orientation: .portrait)}
    }
    
    private func configure(select: NSPopUpButton, orientation: DisplayOrientation) {
        guard let directional = Directional(rawValue: select.tag) else { return }
        let snapAreaConfig = orientation == .landscape
            ? SnapAreaModel.instance.landscape[directional]
            : SnapAreaModel.instance.portrait[directional]
        
        select.removeAllItems()
        select.addItem(withTitle: "-")
        select.menu?.items.first?.tag = -1

        let selectedTag = snapAreaConfig?.action?.rawValue ?? snapAreaConfig?.compound?.rawValue ?? -1

        for compoundSnapArea in CompoundSnapArea.all {
            guard compoundSnapArea.compatibleOrientation.contains(orientation), compoundSnapArea.compatibleDirectionals.contains(directional) else { continue }
            
            let item = NSMenuItem(title: compoundSnapArea.displayName, action: nil, keyEquivalent: "")
            item.tag = compoundSnapArea.rawValue
            select.menu?.addItem(item)
            if selectedTag == item.tag {
                select.select(item)
            }
        }
        select.menu?.addItem(NSMenuItem.separator())
        for windowAction in WindowAction.active {
            if windowAction.isDragSnappable,
                let name = windowAction.displayName {
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.tag = windowAction.rawValue
                item.image = windowAction.image.copy() as? NSImage
                item.image?.size.height = 12
                item.image?.size.width = 18
                select.menu?.addItem(item)
                if selectedTag == item.tag {
                    select.select(item)
                }
            }
        }
    }
}
