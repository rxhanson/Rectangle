//
//  FootprintWindow.swift
//  Rectangle
//
//  Created by Ryan Hanson on 10/17/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Cocoa

class FootprintWindow: NSWindow {
    private var closeCanceled = false
    
    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 0, height: 0)
        super.init(contentRect: initialRect, styleMask: .titled, backing: .buffered, defer: false)

        title = "Rectangle"
        isOpaque = false
        level = .modalPanel
        hasShadow = false
        isReleasedWhenClosed = false
        alphaValue = Defaults.footprintFade.userDisabled
            ? CGFloat(Defaults.footprintAlpha.value)
            : 0
  
        styleMask.insert(.fullSizeContentView)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior.insert(.transient)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.toolbarButton)?.isHidden = true
        
        let boxView = NSBox()
        boxView.boxType = .custom
        boxView.borderColor = .lightGray
        boxView.borderType = .lineBorder
        boxView.borderWidth = CGFloat(Defaults.footprintBorderWidth.value)
        
        if #available(macOS 11.0, *) {
            boxView.cornerRadius = 10
        } else {
            boxView.cornerRadius = 5
        }
        boxView.wantsLayer = true
        boxView.fillColor = Defaults.footprintColor.typedValue?.nsColor ?? NSColor.black
        
        contentView = boxView
    }
    
    override var isVisible: Bool {
        if Defaults.footprintFade.userDisabled {
            return super.isVisible
        } else {
            return alphaValue == Defaults.footprintAlpha.cgFloat
        }
    }
    
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if Defaults.footprintFade.userDisabled {
            super.makeKeyAndOrderFront(sender)
        } else {
            closeCanceled = true
            super.makeKeyAndOrderFront(sender)
            animator().alphaValue = Defaults.footprintAlpha.cgFloat
        }
    }
    
    override func close() {
        if Defaults.footprintFade.userDisabled {
            super.close()
        } else {
            closeCanceled = false
            NSAnimationContext.runAnimationGroup { changes in
                animator().alphaValue = 0.0
            } completionHandler: {
                if !self.closeCanceled {
                    super.close()
                }
            }
        }
    }
}
