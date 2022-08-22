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
    
    var selects: [NSPopUpButton: SnapAreaConfig?]!

    @IBAction func toggleWindowSnapping(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.windowSnapping.enabled = newSetting
        Notification.Name.windowSnapping.post(object: newSetting)
    }
    
    @IBAction func toggleUnsnapRestore(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.unsnapRestore.enabled = newSetting
    }
    
    @IBAction func setLandscapeSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .landscape)
    }

    @IBAction func setPortraitSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .portrait)
    }
    
    private func setSnapArea(sender: NSPopUpButton, type: SnapAreaModelType) {
        guard let directional = Directional(rawValue: sender.tag) else { return }
        let selectedTag = sender.selectedTag()
        var snapAreaConfig: SnapAreaConfig?
        if selectedTag < 0, let complex = ComplexSnapArea(rawValue: selectedTag) {
           snapAreaConfig = SnapAreaConfig(complex: complex)
        } else if selectedTag > 0, let action = WindowAction(rawValue: selectedTag) {
            snapAreaConfig = SnapAreaConfig(action: action)
        }
        SnapAreaModel.instance.setConfig(type: type, directional: directional, snapAreaConfig: snapAreaConfig)
    }
    
    override func viewDidLoad() {
        windowSnappingCheckbox.state = Defaults.windowSnapping.userDisabled ? .off : .on
        unsnapRestoreButton.state = Defaults.unsnapRestore.userDisabled ? .off : .on
        loadSnapAreas()
    }
    
    func loadSnapAreas() {
        let model = SnapAreaModel.instance
        selects = [

            topLeftLandscapeSelect: model.landscape[.tl],
            topLandscapeSelect: model.landscape[.t],
            topRightLandscapeSelect: model.landscape[.tr],
            leftLandscapeSelect: model.landscape[.l],
            rightLandscapeSelect: model.landscape[.r],
            bottomLeftLandscapeSelect: model.landscape[.bl],
            bottomLandscapeSelect: model.landscape[.b],
            bottomRightLandscapeSelect: model.landscape[.br],

            topLeftPortraitSelect: model.portrait[.tl],
            topPortraitSelect: model.portrait[.t],
            topRightPortraitSelect: model.portrait[.tr],
            leftPortraitSelect: model.portrait[.l],
            rightPortraitSelect: model.portrait[.r],
            bottomLeftPortraitSelect: model.portrait[.bl],
            bottomPortraitSelect: model.portrait[.b],
            bottomRightPortraitSelect: model.portrait[.br]

        ]
        
        selects.forEach { self.configure(select: $0, usingConfig: $1)}
    }
    
    private func configure(select: NSPopUpButton, usingConfig snapAreaConfig: SnapAreaConfig?) {
        for complexSnapArea in ComplexSnapArea.all {
            let item = NSMenuItem(title: complexSnapArea.displayName, action: nil, keyEquivalent: "")
            item.tag = complexSnapArea.rawValue
            select.menu?.addItem(item)
            if let complex = snapAreaConfig?.complex, complex == complexSnapArea {
                select.selectItem(withTag: complexSnapArea.rawValue)
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
                if let action = snapAreaConfig?.action,
                    action == windowAction {
                    select.selectItem(withTag: windowAction.rawValue)
                }
            }
        }
    }
}

enum ComplexSnapArea: Int, Codable {
    case leftTopBottomHalf = -1, rightTopBottomHalf = -2, thirds = -3
    
    var displayName: String {
        switch self {
        case .leftTopBottomHalf:
            return "Left half, top/bottom half near corners"
        case .rightTopBottomHalf:
            return "Right half, top/bottom half near corners"
        case .thirds:
            return "Thirds, drag toward center for two thirds"
        }
    }
    
    static let all = [leftTopBottomHalf, rightTopBottomHalf, thirds]
}

struct SnapAreaConfig: Codable {
    let complex: ComplexSnapArea?   
    let action: WindowAction?
    
    init(complex: ComplexSnapArea? = nil, action: WindowAction? = nil) {
        self.complex = complex
        self.action = action
    }
}

enum Directional: Int, Codable {
    case tl = 1,
         t = 2,
         tr = 3,
         l = 4,
         r = 5,
         bl = 6,
         b = 7,
         br = 8,
         c = 9
    
    static var cases = [tl, t, tr, l, r, bl, b, br]
}
