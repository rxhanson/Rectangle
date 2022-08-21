//
//  SnapAreaViewController.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/13/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Cocoa

class SnapAreaViewController: NSViewController {
    
    @IBOutlet weak var topLeftSelect: NSPopUpButton!
    @IBOutlet weak var topSelect: NSPopUpButton!
    @IBOutlet weak var topRightSelect: NSPopUpButton!
    @IBOutlet weak var leftSelect: NSPopUpButton!
    @IBOutlet weak var rightSelect: NSPopUpButton!
    @IBOutlet weak var bottomLeftSelect: NSPopUpButton!
    @IBOutlet weak var bottomSelect: NSPopUpButton!
    @IBOutlet weak var bottomRightSelect: NSPopUpButton!
    
    @IBOutlet weak var verticalStackView: NSStackView!
    
    @IBOutlet weak var topLeftVerticalSelect: NSPopUpButton!
    @IBOutlet weak var topVerticalSelect: NSPopUpButton!
    @IBOutlet weak var topRightVerticalSelect: NSPopUpButton!
    @IBOutlet weak var leftVerticalSelect: NSPopUpButton!
    @IBOutlet weak var rightVerticalSelect: NSPopUpButton!
    @IBOutlet weak var bottomLeftVerticalSelect: NSPopUpButton!
    @IBOutlet weak var bottomVerticalSelect: NSPopUpButton!
    @IBOutlet weak var bottomRightVerticalSelect: NSPopUpButton!
    
    var horizontalSelects: [NSPopUpButton: SnapAreaConfig?]!
    var verticalSelects: [NSPopUpButton: SnapAreaConfig?]!

    @IBAction func setHorizontalSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .horizontal)
    }

    @IBAction func setVerticalSnapArea(_ sender: NSPopUpButton) {
        setSnapArea(sender: sender, type: .vertical)
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
        load()
    }
    
    func load() {
        let model = SnapAreaModel.instance
        let horizontalModel = model.horizontal
        horizontalSelects = [
            topLeftSelect: horizontalModel[.tl],
            topSelect: horizontalModel[.t],
            topRightSelect: horizontalModel[.tr],
            leftSelect: horizontalModel[.l],
            rightSelect: horizontalModel[.r],
            bottomLeftSelect: horizontalModel[.bl],
            bottomSelect: horizontalModel[.b],
            bottomRightSelect: horizontalModel[.br]
        ]
        let verticalModel = model.vertical
        verticalSelects = [
            topLeftVerticalSelect: verticalModel[.tl],
            topVerticalSelect: verticalModel[.t],
            topRightVerticalSelect: verticalModel[.tr],
            leftVerticalSelect: verticalModel[.l],
            rightVerticalSelect: verticalModel[.r],
            bottomLeftVerticalSelect: verticalModel[.bl],
            bottomVerticalSelect: verticalModel[.b],
            bottomRightVerticalSelect: verticalModel[.br]
        ]
        
        for (select, snapAreaConfig) in horizontalSelects {
            for windowAction in WindowAction.active {
                if windowAction.isDragSnappable,
                    let name = windowAction.displayName {
                    let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                    item.tag = windowAction.rawValue
                    select.menu?.addItem(item)
                    if let action = snapAreaConfig?.action,
                        action == windowAction {
                        select.selectItem(withTag: windowAction.rawValue)
                    }
                }
            }
        }
    }
}

enum ComplexSnapArea: Int, Codable {
    case leftTopBottomHalf = -1, rightTopBottomHalf = -2, thirds = -3
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
