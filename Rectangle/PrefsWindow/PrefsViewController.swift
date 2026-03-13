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
    @IBOutlet weak var centerTwoThirdsShortcutView: MASShortcutView!
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
    @IBOutlet weak var centerThreeFourthsShortcutView: MASShortcutView!
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
        ]

        setupCategoryShortcuts()

        for (action, view) in actionsToViews {
            view.setAssociatedUserDefaultsKey(action.name, withTransformerName: MASDictionaryTransformerName)
        }

        if Defaults.allowAnyShortcut.enabled {
            let passThroughValidator = PassthroughShortcutValidator()
            actionsToViews.values.forEach { $0.shortcutValidator = passThroughValidator }
        }

        subscribeToAllowAnyShortcutToggle()

        additionalShortcutsStackView.isHidden = false
        showMoreButton.title = "▼"
    }

    private var extraSectionsAdded = false

    private func setupCategoryShortcuts() {
        guard !extraSectionsAdded else { return }
        extraSectionsAdded = true

        guard let leftColumn = additionalShortcutsStackView.arrangedSubviews.first as? NSStackView,
              let rightColumn = additionalShortcutsStackView.arrangedSubviews.last as? NSStackView else { return }

        for view in leftColumn.arrangedSubviews {
            leftColumn.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in rightColumn.arrangedSubviews {
            rightColumn.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        leftColumn.addArrangedSubview(createShortcutRow(for: .firstThird, label: "Thirds"))
        leftColumn.addArrangedSubview(createShortcutRow(for: .firstFourth, label: "Fourths"))
        leftColumn.addArrangedSubview(createShortcutRow(for: .topLeftSixth, label: "Sixths"))

        rightColumn.addArrangedSubview(createShortcutRow(for: .topLeftEighth, label: "Eighths"))

        leftColumn.addArrangedSubview(createSectionSpacer())
        rightColumn.addArrangedSubview(createSectionSpacer())
        leftColumn.addArrangedSubview(createSectionHeader(title: "Move to Edge"))
        rightColumn.addArrangedSubview(createSectionSeparator())
        leftColumn.addArrangedSubview(createSectionSpacer())
        rightColumn.addArrangedSubview(createSectionSpacer())

        leftColumn.addArrangedSubview(createShortcutRow(for: .moveLeft))
        leftColumn.addArrangedSubview(createShortcutRow(for: .moveUp))
        rightColumn.addArrangedSubview(createShortcutRow(for: .moveRight))
        rightColumn.addArrangedSubview(createShortcutRow(for: .moveDown))
    }

    private func createSectionSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 5).isActive = true
        return spacer
    }

    private func createSectionHeader(title: String) -> NSView {
        let separator = createSectionSeparator()
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSStackView(views: [separator, label])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }

    private func createSectionSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func createShortcutRow(for action: WindowAction, label customLabel: String? = nil) -> NSStackView {
        let shortcutView = MASShortcutView()
        shortcutView.translatesAutoresizingMaskIntoConstraints = false
        shortcutView.widthAnchor.constraint(equalToConstant: 160).isActive = true
        shortcutView.heightAnchor.constraint(equalToConstant: 19).isActive = true

        let label = customLabel ?? action.displayName ?? action.name
        let textField = NSTextField(labelWithString: label)
        textField.alignment = .right
        textField.lineBreakMode = .byClipping
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.init(251), for: .horizontal)
        textField.setContentHuggingPriority(.init(750), for: .vertical)

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 21).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 14).isActive = true
        imageView.image = action.image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setContentHuggingPriority(.init(251), for: .horizontal)
        imageView.setContentHuggingPriority(.init(251), for: .vertical)

        let labelStack = NSStackView(views: [textField, imageView])
        labelStack.orientation = .horizontal
        labelStack.alignment = .centerY
        labelStack.distribution = .fill

        let row = NSStackView(views: [labelStack, shortcutView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 18

        actionsToViews[action] = shortcutView
        return row
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
