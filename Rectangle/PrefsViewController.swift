//
//  PrefsViewController.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/18/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import MASShortcut
import ServiceManagement

class PrefsViewController: NSViewController {
    
    var actionsToViews = [WindowAction: MASShortcutView]()
    
    @IBOutlet weak var leftHalfShortcutView: MASShortcutView!
    @IBOutlet weak var rightHalfShortcutView: MASShortcutView!
    @IBOutlet weak var centerHalfShortcutView: MASShortcutView!
    @IBOutlet weak var topHalfShortcutView: MASShortcutView!
    @IBOutlet weak var bottomHalfShortcutView: MASShortcutView!
    
    @IBOutlet weak var topLeftShortcutView: MASShortcutView!
    @IBOutlet weak var topRightShortcutView: MASShortcutView!
    @IBOutlet weak var bottomLeftShortcutView: MASShortcutView!
    @IBOutlet weak var bottomRightShortcutView: MASShortcutView!
    
    @IBOutlet weak var nextDisplayShortcutView: MASShortcutView!
    @IBOutlet weak var previousDisplayShortcutView: MASShortcutView!
    
    @IBOutlet weak var makeLargerShortcutView: MASShortcutView!
    @IBOutlet weak var makeSmallerShortcutView: MASShortcutView!
    
    @IBOutlet weak var maximizeShortcutView: MASShortcutView!
    @IBOutlet weak var almostMaximizeShortcutView: MASShortcutView!
    @IBOutlet weak var maximizeHeightShortcutView: MASShortcutView!
    @IBOutlet weak var centerShortcutView: MASShortcutView!
    @IBOutlet weak var restoreShortcutView: MASShortcutView!
    
    // Additional
    @IBOutlet weak var firstThirdShortcutView: MASShortcutView!
    @IBOutlet weak var firstTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var centerThirdShortcutView: MASShortcutView!
    @IBOutlet weak var lastTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var lastThirdShortcutView: MASShortcutView!
    
    @IBOutlet weak var moveLeftShortcutView: MASShortcutView!
    @IBOutlet weak var moveRightShortcutView: MASShortcutView!
    @IBOutlet weak var moveUpShortcutView: MASShortcutView!
    @IBOutlet weak var moveDownShortcutView: MASShortcutView!
    
    @IBOutlet weak var firstFourthShortcutView: MASShortcutView!
    @IBOutlet weak var secondFourthShortcutView: MASShortcutView!
    @IBOutlet weak var thirdFourthShortcutView: MASShortcutView!
    @IBOutlet weak var lastFourthShortcutView: MASShortcutView!
    @IBOutlet weak var firstThreeFourthsShortcutView: MASShortcutView!
    @IBOutlet weak var lastThreeFourthsShortcutView: MASShortcutView!
    
    @IBOutlet weak var topLeftSixthShortcutView: MASShortcutView!
    @IBOutlet weak var topCenterSixthShortcutView: MASShortcutView!
    @IBOutlet weak var topRightSixthShortcutView: MASShortcutView!
    @IBOutlet weak var bottomLeftSixthShortcutView: MASShortcutView!
    @IBOutlet weak var bottomCenterSixthShortcutView: MASShortcutView!
    @IBOutlet weak var bottomRightSixthShortcutView: MASShortcutView!

    
    @IBOutlet weak var showMoreButton: NSButton!
    @IBOutlet weak var additionalShortcutsStackView: NSStackView!
    
    // Settings
    override func awakeFromNib() {
        
        actionsToViews = [
            .leftHalf: leftHalfShortcutView,
            .rightHalf: rightHalfShortcutView,
            .centerHalf: centerHalfShortcutView,
            .topHalf: topHalfShortcutView,
            .bottomHalf: bottomHalfShortcutView,
            .topLeft: topLeftShortcutView,
            .topRight: topRightShortcutView,
            .bottomLeft: bottomLeftShortcutView,
            .bottomRight: bottomRightShortcutView,
            .nextDisplay: nextDisplayShortcutView,
            .previousDisplay: previousDisplayShortcutView,
            .maximize: maximizeShortcutView,
            .almostMaximize: almostMaximizeShortcutView,
            .maximizeHeight: maximizeHeightShortcutView,
            .center: centerShortcutView,
            .larger: makeLargerShortcutView,
            .smaller: makeSmallerShortcutView,
            .restore: restoreShortcutView,
            .firstThird: firstThirdShortcutView,
            .firstTwoThirds: firstTwoThirdsShortcutView,
            .centerThird: centerThirdShortcutView,
            .lastTwoThirds: lastTwoThirdsShortcutView,
            .lastThird: lastThirdShortcutView,
            .moveLeft: moveLeftShortcutView,
            .moveRight: moveRightShortcutView,
            .moveUp: moveUpShortcutView,
            .moveDown: moveDownShortcutView,
            .firstFourth: firstFourthShortcutView,
            .secondFourth: secondFourthShortcutView,
            .thirdFourth: thirdFourthShortcutView,
            .lastFourth: lastFourthShortcutView,
            .firstThreeFourths: firstThreeFourthsShortcutView,
            .lastThreeFourths: lastThreeFourthsShortcutView,
            .topLeftSixth: topLeftSixthShortcutView,
            .topCenterSixth: topCenterSixthShortcutView,
            .topRightSixth: topRightSixthShortcutView,
            .bottomLeftSixth: bottomLeftSixthShortcutView,
            .bottomCenterSixth: bottomCenterSixthShortcutView,
            .bottomRightSixth: bottomRightSixthShortcutView
        ]
        
        for (action, view) in actionsToViews {
            view.setAssociatedUserDefaultsKey(action.name, withTransformerName: MASDictionaryTransformerName)
        }
        
        if Defaults.allowAnyShortcut.enabled {
            let passThroughValidator = PassthroughShortcutValidator()
            actionsToViews.values.forEach { $0.shortcutValidator = passThroughValidator }
        }
        
        subscribeToAllowAnyShortcutToggle()
        
        additionalShortcutsStackView.isHidden = true
    }
    
    @IBAction func toggleShowMore(_ sender: NSButton) {
        additionalShortcutsStackView.isHidden = !additionalShortcutsStackView.isHidden
        showMoreButton.title = additionalShortcutsStackView.isHidden
            ? "▶︎ ⋯" : "▼"
    }
    
    private func subscribeToAllowAnyShortcutToggle() {
        Notification.Name.allowAnyShortcut.onPost { notification in
            guard let enabled = notification.object as? Bool else { return }
            let validator = enabled ? PassthroughShortcutValidator() : MASShortcutValidator()
            self.actionsToViews.values.forEach { $0.shortcutValidator = validator }
        }
    }
    
}

class PassthroughShortcutValidator: MASShortcutValidator {
    
    override func isShortcutValid(_ shortcut: MASShortcut!) -> Bool {
        return true
    }
    
    override func isShortcutAlreadyTaken(bySystem shortcut: MASShortcut!, explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        return false
    }
    
    override func isShortcut(_ shortcut: MASShortcut!, alreadyTakenIn menu: NSMenu!, explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        return false
    }
    
}
