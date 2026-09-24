/// ExtraSettingsPopover.swift

import MASShortcut

extension SettingsViewController {
    
    func showExtraSettingsPopover(_ sender: NSButton) {
        if extraSettingsPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            let viewController = NSViewController()

            let mainStackView = NSStackView()
            mainStackView.orientation = .vertical
            mainStackView.alignment = .leading
            mainStackView.spacing = 5
            mainStackView.translatesAutoresizingMaskIntoConstraints = false

            let headerLabel = NSTextField(labelWithString: NSLocalizedString("Extra Shortcuts", tableName: "Main", value: "", comment: ""))
            headerLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            headerLabel.alignment = .center
            headerLabel.translatesAutoresizingMaskIntoConstraints = false

            let tileRowsLabel = NSTextField(labelWithString: NSLocalizedString("tileRows.title", tableName: "Main", value: "Tile Windows in Rows", comment: ""))
            tileRowsLabel.alignment = .right
            tileRowsLabel.translatesAutoresizingMaskIntoConstraints = false
            let tileColumnsLabel = NSTextField(labelWithString: NSLocalizedString("tileColumns.title", tableName: "Main", value: "Tile Windows in Columns", comment: ""))
            tileColumnsLabel.alignment = .right
            tileColumnsLabel.translatesAutoresizingMaskIntoConstraints = false
            let largerWidthLabel = NSTextField(labelWithString: NSLocalizedString("Larger Width", tableName: "Main", value: "", comment: ""))
            largerWidthLabel.alignment = .right
            let smallerWidthLabel = NSTextField(labelWithString: NSLocalizedString("Smaller Width", tableName: "Main", value: "", comment: ""))
            smallerWidthLabel.alignment = .right
            let widthStepLabel = NSTextField(labelWithString: NSLocalizedString("Width Step (px)", tableName: "Main", value: "", comment: ""))
            widthStepLabel.alignment = .right
            
            let topVerticalThirdLabel = NSTextField(labelWithString: NSLocalizedString("Top Third", tableName: "Main", value: "", comment: ""))
            topVerticalThirdLabel.alignment = .right
            let middleVerticalThirdLabel = NSTextField(labelWithString: NSLocalizedString("Middle Third", tableName: "Main", value: "", comment: ""))
            middleVerticalThirdLabel.alignment = .right
            let bottomVerticalThirdLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Third", tableName: "Main", value: "", comment: ""))
            bottomVerticalThirdLabel.alignment = .right
            let topVerticalTwoThirdsLabel = NSTextField(labelWithString: NSLocalizedString("Top Two Thirds", tableName: "Main", value: "", comment: ""))
            topVerticalTwoThirdsLabel.alignment = .right
            let bottomVerticalTwoThirdsLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Two Thirds", tableName: "Main", value: "", comment: ""))
            bottomVerticalTwoThirdsLabel.alignment = .right

            let topLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Left Eighth", tableName: "Main", value: "", comment: ""))
            topLeftEighthLabel.alignment = .right
            let topCenterLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Left Eighth", tableName: "Main", value: "", comment: ""))
            topCenterLeftEighthLabel.alignment = .right
            let topCenterRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Center Right Eighth", tableName: "Main", value: "", comment: ""))
            topCenterRightEighthLabel.alignment = .right
            let topRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Top Right Eighth", tableName: "Main", value: "", comment: ""))
            topRightEighthLabel.alignment = .right
            let bottomLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Left Eighth", tableName: "Main", value: "", comment: ""))
            bottomLeftEighthLabel.alignment = .right
            let bottomCenterLeftEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Left Eighth", tableName: "Main", value: "", comment: ""))
            bottomCenterLeftEighthLabel.alignment = .right
            let bottomCenterRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Center Right Eighth", tableName: "Main", value: "", comment: ""))
            bottomCenterRightEighthLabel.alignment = .right
            let bottomRightEighthLabel = NSTextField(labelWithString: NSLocalizedString("Bottom Right Eighth", tableName: "Main", value: "", comment: ""))
            bottomRightEighthLabel.alignment = .right

            let widthStepField = AutoSaveFloatField(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            widthStepField.stringValue = String(Int(Defaults.widthStepSize.value))
            widthStepField.delegate = self
            widthStepField.defaults = Defaults.widthStepSize
            widthStepField.translatesAutoresizingMaskIntoConstraints = false
            widthStepField.refusesFirstResponder = true
            widthStepField.alignment = .right

            let integerFormatter = NumberFormatter()
            integerFormatter.allowsFloats = false
            integerFormatter.minimum = 1
            widthStepField.formatter = integerFormatter

            let splitRatioHeaderLabel = NSTextField(labelWithString: NSLocalizedString("Side Split Ratio", tableName: "Main", value: "", comment: ""))
            splitRatioHeaderLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            splitRatioHeaderLabel.alignment = .center
            splitRatioHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

            let hSplitLabel = NSTextField(labelWithString: NSLocalizedString("Horizontal (L/R, %)", tableName: "Main", value: "", comment: ""))
            hSplitLabel.alignment = .right
            hSplitLabel.translatesAutoresizingMaskIntoConstraints = false

            let vSplitLabel = NSTextField(labelWithString: NSLocalizedString("Vertical (T/B, %)", tableName: "Main", value: "", comment: ""))
            vSplitLabel.alignment = .right
            vSplitLabel.translatesAutoresizingMaskIntoConstraints = false

            let percentFormatter = NumberFormatter()
            percentFormatter.allowsFloats = false
            percentFormatter.minimum = 1
            percentFormatter.maximum = 99

            let hSplitField = AutoSaveFloatField(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            hSplitField.stringValue = String(Int(Defaults.horizontalSplitRatio.value))
            hSplitField.delegate = self
            hSplitField.defaults = Defaults.horizontalSplitRatio
            hSplitField.fallbackValue = 50
            hSplitField.translatesAutoresizingMaskIntoConstraints = false
            hSplitField.refusesFirstResponder = true
            hSplitField.alignment = .right
            hSplitField.formatter = percentFormatter

            let hSplitPopUpButton = HalfSplitRatioPopUpButton()
            hSplitPopUpButton.translatesAutoresizingMaskIntoConstraints = false
            hSplitPopUpButton.target = self
            hSplitPopUpButton.action = #selector(didSelectHalfSplitRatioPreset(sender:))
            hSplitPopUpButton.defaults = Defaults.horizontalSplitRatio
            hSplitPopUpButton.customField = hSplitField
            configureHalfSplitRatioPopUpButton(hSplitPopUpButton)

            let vSplitField = AutoSaveFloatField(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            vSplitField.stringValue = String(Int(Defaults.verticalSplitRatio.value))
            vSplitField.delegate = self
            vSplitField.defaults = Defaults.verticalSplitRatio
            vSplitField.fallbackValue = 50
            vSplitField.translatesAutoresizingMaskIntoConstraints = false
            vSplitField.refusesFirstResponder = true
            vSplitField.alignment = .right
            vSplitField.formatter = percentFormatter

            let vSplitPopUpButton = HalfSplitRatioPopUpButton()
            vSplitPopUpButton.translatesAutoresizingMaskIntoConstraints = false
            vSplitPopUpButton.target = self
            vSplitPopUpButton.action = #selector(didSelectHalfSplitRatioPreset(sender:))
            vSplitPopUpButton.defaults = Defaults.verticalSplitRatio
            vSplitPopUpButton.customField = vSplitField
            configureHalfSplitRatioPopUpButton(vSplitPopUpButton)

            hSplitField.defaultsSetAction = { [weak hSplitPopUpButton] in
                hSplitPopUpButton?.selectCurrentValue()
            }
            vSplitField.defaultsSetAction = { [weak vSplitPopUpButton] in
                vSplitPopUpButton?.selectCurrentValue()
            }

            let widthStepRow = NSStackView()
            widthStepRow.orientation = .horizontal
            widthStepRow.alignment = .centerY
            widthStepRow.spacing = 18
            widthStepRow.addArrangedSubview(widthStepLabel)
            widthStepRow.addArrangedSubview(widthStepField)

            let hSplitRow = NSStackView()
            hSplitRow.orientation = .horizontal
            hSplitRow.alignment = .centerY
            hSplitRow.spacing = 18
            hSplitRow.addArrangedSubview(hSplitLabel)
            let hSplitControlsStack = NSStackView()
            hSplitControlsStack.orientation = .horizontal
            hSplitControlsStack.alignment = .centerY
            hSplitControlsStack.spacing = 8
            hSplitControlsStack.addArrangedSubview(hSplitPopUpButton)
            hSplitControlsStack.addArrangedSubview(hSplitField)
            hSplitRow.addArrangedSubview(hSplitControlsStack)

            let vSplitRow = NSStackView()
            vSplitRow.orientation = .horizontal
            vSplitRow.alignment = .centerY
            vSplitRow.spacing = 18
            vSplitRow.addArrangedSubview(vSplitLabel)
            let vSplitControlsStack = NSStackView()
            vSplitControlsStack.orientation = .horizontal
            vSplitControlsStack.alignment = .centerY
            vSplitControlsStack.spacing = 8
            vSplitControlsStack.addArrangedSubview(vSplitPopUpButton)
            vSplitControlsStack.addArrangedSubview(vSplitField)
            vSplitRow.addArrangedSubview(vSplitControlsStack)
            
            mainStackView.addArrangedSubview(headerLabel)
            mainStackView.setCustomSpacing(10, after: headerLabel)

            let tileGridHeaderLabel = NSTextField(labelWithString: NSLocalizedString("Tile Windows in Rows/Columns", tableName: "Main", value: "", comment: "General settings group for multi-window grid limits"))
            tileGridHeaderLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            tileGridHeaderLabel.alignment = .center
            tileGridHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

            let columnsLimitRow = TileGridLimitRow(
                title: NSLocalizedString("Maximum windows per column", tableName: "Main", value: "", comment: "Maximum windows stacked in each tiled column"),
                defaults: Defaults.tileColumnsMaxWindows)
            let rowsLimitRow = TileGridLimitRow(
                title: NSLocalizedString("Maximum windows per row", tableName: "Main", value: "", comment: "Maximum windows placed side by side in each tiled row"),
                defaults: Defaults.tileRowsMaxWindows)
            tileGridLimitRows = [columnsLimitRow, rowsLimitRow]
            mainStackView.addArrangedSubview(tileGridHeaderLabel)
            mainStackView.addArrangedSubview(columnsLimitRow)
            mainStackView.addArrangedSubview(rowsLimitRow)
            mainStackView.setCustomSpacing(10, after: rowsLimitRow)

            mainStackView.addArrangedSubview(widthStepRow)
            // Grid Positions - cycling shortcuts for larger grids
            let showAdditionalSizesCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Show additional sizes in menu", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleShowAdditionalSizesInMenu(_:)))
            showAdditionalSizesCheckbox.state = Defaults.showAdditionalSizesInMenu.userEnabled ? .on : .off
            showAdditionalSizesCheckbox.translatesAutoresizingMaskIntoConstraints = false
            showAdditionalSizesCheckbox.alignment = .left
            showAdditionalSizesCheckbox.imageHugsTitle = true

            let gridHeaderLabel = NSTextField(labelWithString: NSLocalizedString("Grid Positions", tableName: "Main", value: "", comment: ""))
            gridHeaderLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            gridHeaderLabel.alignment = .center
            gridHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

            let cyclingHintLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Press the shortcut repeatedly to cycle through all positions in the grid.", tableName: "Main", value: "", comment: ""))
            cyclingHintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            cyclingHintLabel.textColor = .secondaryLabelColor
            cyclingHintLabel.alignment = .center
            cyclingHintLabel.translatesAutoresizingMaskIntoConstraints = false

            // Cycling shortcut rows - Ninths, Twelfths, Sixteenths
            let ninthsCyclingLabel = NSTextField(labelWithString: NSLocalizedString("Ninths (3\u{00d7}3)", tableName: "Main", value: "", comment: ""))
            ninthsCyclingLabel.alignment = .right
            ninthsCyclingLabel.translatesAutoresizingMaskIntoConstraints = false
            let twelfthsCyclingLabel = NSTextField(labelWithString: NSLocalizedString("Twelfths (4\u{00d7}3)", tableName: "Main", value: "", comment: ""))
            twelfthsCyclingLabel.alignment = .right
            twelfthsCyclingLabel.translatesAutoresizingMaskIntoConstraints = false

            let sixteenthsCyclingLabel = NSTextField(labelWithString: NSLocalizedString("Sixteenths (4\u{00d7}4)", tableName: "Main", value: "", comment: ""))
            sixteenthsCyclingLabel.alignment = .right
            sixteenthsCyclingLabel.translatesAutoresizingMaskIntoConstraints = false


            let ninthsCyclingIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            ninthsCyclingIcon.image = WindowAction.topLeftNinth.image
            ninthsCyclingIcon.image?.size = NSSize(width: 21, height: 14)
            let twelfthsCyclingIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            twelfthsCyclingIcon.image = WindowAction.topLeftTwelfth.image
            twelfthsCyclingIcon.image?.size = NSSize(width: 21, height: 14)
            let sixteenthsCyclingIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 21, height: 14))
            sixteenthsCyclingIcon.image = WindowAction.topLeftSixteenth.image
            sixteenthsCyclingIcon.image?.size = NSSize(width: 21, height: 14)

            func makeLabelStack(_ label: NSTextField, _ icon: NSImageView) -> NSStackView {
                let stack = NSStackView()
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 8
                stack.addArrangedSubview(label)
                stack.addArrangedSubview(icon)
                return stack
            }

            let overlapOffsetCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Offset window position on overlap", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleCyclingOverlapOffset(_:)))
            overlapOffsetCheckbox.state = Defaults.cyclingOverlapOffset.userEnabled ? .on : .off
            overlapOffsetCheckbox.translatesAutoresizingMaskIntoConstraints = false
            overlapOffsetCheckbox.alignment = .left

            let stackBadgeCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Show stacked window list on hover", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleStackBadge(_:)))
            self.stackBadgeCheckbox = stackBadgeCheckbox
            stackBadgeCheckbox.state = Defaults.stackBadge.userEnabled ? .on : .off
            stackBadgeCheckbox.translatesAutoresizingMaskIntoConstraints = false
            stackBadgeCheckbox.alignment = .left

            let stackBadgeToggleLabel = NSTextField(labelWithString: NSLocalizedString("Toggle window list", tableName: "Main", value: "", comment: ""))
            stackBadgeToggleLabel.alignment = .right
            stackBadgeToggleLabel.translatesAutoresizingMaskIntoConstraints = false
            let stackBadgeToggleShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 19))
            stackBadgeToggleShortcutView.setAssociatedUserDefaultsKey(StackBadgeManager.toggleDefaultsKey, withTransformerName: MASDictionaryTransformerName)
            stackBadgeToggleShortcutView.translatesAutoresizingMaskIntoConstraints = false
            stackBadgeToggleShortcutView.shortcutValidator = AppShortcutValidator(defaultsKey: StackBadgeManager.toggleDefaultsKey)
            shortcutRecordingObserver.observe([stackBadgeToggleShortcutView])
            let stackBadgeToggleRow = NSStackView()
            stackBadgeToggleRow.orientation = .horizontal
            stackBadgeToggleRow.alignment = .centerY
            stackBadgeToggleRow.spacing = 18
            stackBadgeToggleRow.addArrangedSubview(stackBadgeToggleLabel)
            stackBadgeToggleRow.addArrangedSubview(stackBadgeToggleShortcutView)

            mainStackView.addArrangedSubview(gridHeaderLabel)
            mainStackView.setCustomSpacing(4, after: gridHeaderLabel)
            mainStackView.addArrangedSubview(cyclingHintLabel)
            mainStackView.setCustomSpacing(8, after: cyclingHintLabel)
            mainStackView.addArrangedSubview(showAdditionalSizesCheckbox)
            mainStackView.addArrangedSubview(overlapOffsetCheckbox)
            mainStackView.addArrangedSubview(stackBadgeCheckbox)
            mainStackView.setCustomSpacing(6, after: stackBadgeCheckbox)
            mainStackView.addArrangedSubview(stackBadgeToggleRow)
            mainStackView.setCustomSpacing(8, after: stackBadgeToggleRow)


            mainStackView.addArrangedSubview(splitRatioHeaderLabel)
            mainStackView.setCustomSpacing(10, after: splitRatioHeaderLabel)
            mainStackView.addArrangedSubview(hSplitRow)
            mainStackView.addArrangedSubview(vSplitRow)

            let halvesCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Half actions preserve the window's size on the other axis", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleHalvesPreserveOtherAxisSize(_:)))
            halvesCheckbox.state = Defaults.halvesPreserveOtherAxisSize.enabled ? .on : .off
            halvesCheckbox.toolTip = NSLocalizedString("Left Half then Top Half moves the window to the top left quarter; the action for the opposite edge expands it back.", tableName: "Main", value: "", comment: "")
            halvesCheckbox.translatesAutoresizingMaskIntoConstraints = false
            halvesCheckbox.alignment = .left

            mainStackView.setCustomSpacing(8, after: vSplitRow)
            mainStackView.addArrangedSubview(halvesCheckbox)
            halvesPreserveOtherAxisSizeCheckbox = halvesCheckbox

            let repeatedMaximizeCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Repeated maximize restores the previous size and position", tableName: "Main", value: "", comment: ""), target: self, action: #selector(toggleRepeatedMaximizeRestoresPrevious(_:)))
            repeatedMaximizeCheckbox.state = Defaults.repeatedMaximizeRestoresPrevious.enabled ? .on : .off
            repeatedMaximizeCheckbox.toolTip = NSLocalizedString("After Rectangle maximizes or almost maximizes a window, executing the same action again moves the window back to its previous size and position.", tableName: "Main", value: "", comment: "")
            repeatedMaximizeCheckbox.translatesAutoresizingMaskIntoConstraints = false
            repeatedMaximizeCheckbox.alignment = .left

            mainStackView.addArrangedSubview(repeatedMaximizeCheckbox)
            repeatedMaximizeRestoresPreviousCheckbox = repeatedMaximizeCheckbox

            let containerView = NSView()
            containerView.addSubview(mainStackView)

            NSLayoutConstraint.activate([
                mainStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
                mainStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
                mainStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
                mainStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -15)
            ])

            viewController.view = containerView
            popover.contentViewController = viewController
            extraSettingsPopover = popover
        }
        tileGridLimitRows.forEach { $0.reload() }
        extraSettingsPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
 
    @objc private func didSelectHalfSplitRatioPreset(sender: Any?) {
        guard let popUpButton = sender as? HalfSplitRatioPopUpButton,
              let defaults = popUpButton.defaults else {
            Logger.log("Expected action to be sent from HalfSplitRatioPopUpButton. Instead, sender is: \(String(describing: sender))")
            return
        }
        
        guard popUpButton.selectedTag() != HalfSplitRatioPopUpButton.otherTag else {
            popUpButton.customField?.isHidden = false
            return
        }
        
        guard let cycleSize = CycleSize(rawValue: popUpButton.selectedTag()) else {
            Logger.log("Expected tag of half split ratio popup to match a value of CycleSize. Got: \(String(describing: popUpButton.selectedTag()))")
            return
        }
        
        defaults.value = cycleSize.percentValue
        ActiveSideSplitRatios.shared.resetAll()
        popUpButton.customField?.stringValue = "\(Int(round(cycleSize.percentValue)))"
        popUpButton.customField?.isHidden = true
    }
    
    private func configureHalfSplitRatioPopUpButton(_ popUpButton: HalfSplitRatioPopUpButton) {
        popUpButton.removeAllItems()
        
        CycleSize.sortedSizes.forEach { cycleSize in
            popUpButton.addItem(withTitle: cycleSize.title)
            popUpButton.lastItem?.tag = cycleSize.rawValue
        }
        
        popUpButton.addItem(withTitle: NSLocalizedString("Other", tableName: "Main", value: "", comment: ""))
        popUpButton.lastItem?.tag = HalfSplitRatioPopUpButton.otherTag
        popUpButton.selectCurrentValue()
    }
    
}

class TileGridLimitRow: NSStackView, NSTextFieldDelegate {
    private let defaults: PositiveIntDefault
    private let field = NSTextField()
    private let stepper = NSStepper()

    init(title: String, defaults: PositiveIntDefault) {
        self.defaults = defaults
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = NSNumber(value: Int.max)
        field.formatter = formatter
        field.delegate = self
        field.alignment = .right
        field.refusesFirstResponder = false
        field.setAccessibilityLabel(title)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true

        stepper.minValue = 1
        stepper.maxValue = Double(Int.max)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepLimit(_:))
        stepper.setAccessibilityLabel(title)

        let controls: [NSControl] = [label, field, stepper]
        controls.forEach { control in
            control.setContentCompressionResistancePriority(.required, for: .vertical)
            control.setContentHuggingPriority(.defaultHigh, for: .vertical)
            addArrangedSubview(control)
        }
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("TileGridLimitRow is created programmatically")
    }

    func reload() {
        field.stringValue = String(defaults.value)
        stepper.doubleValue = Double(defaults.value)
    }

    @objc private func stepLimit(_ sender: NSStepper) {
        defaults.value = Int(exactly: sender.doubleValue) ?? Int.max
        reload()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let value = Int(field.stringValue), value > 0 {
            defaults.value = value
            stepper.doubleValue = Double(defaults.value)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        reload()
    }
}
