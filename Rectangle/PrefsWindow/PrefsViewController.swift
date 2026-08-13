/// PrefsViewController.swift

import Cocoa
import MASShortcut
import ServiceManagement

class PrefsViewController: NSViewController {
    
    var actionsToViews = [WindowAction: MASShortcutView]()
    private let shortcutRecordingObserver = ShortcutRecordingObserver()
    
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

    private var presetPopUpButton: NSPopUpButton?

    private enum PresetMenuAction: Int {
        case newFromDefaults = 1
        case duplicate = 2
        case rename = 3
        case delete = 4
    }


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
            .centerTwoThirds: centerTwoThirdsShortcutView,
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
            .centerThreeFourths: centerThreeFourthsShortcutView,
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
        shortcutRecordingObserver.observe(Array(actionsToViews.values))
        
        if Defaults.allowAnyShortcut.enabled {
            let passThroughValidator = PassthroughShortcutValidator()
            actionsToViews.values.forEach { $0.shortcutValidator = passThroughValidator }
        }
        
        subscribeToAllowAnyShortcutToggle()

        additionalShortcutsStackView.isHidden = true

        initializePresetPicker()
        subscribeToConfigImported()
    }
    
    @IBAction func toggleShowMore(_ sender: NSButton) {
        additionalShortcutsStackView.isHidden = !additionalShortcutsStackView.isHidden
        showMoreButton.title = additionalShortcutsStackView.isHidden
            ? "▶︎ ⋯" : "▼"
    }

    private func initializePresetPicker() {
        guard let mainStack = additionalShortcutsStackView.superview as? NSStackView else { return }

        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
        popUpButton.target = self
        popUpButton.action = #selector(presetSelectionChanged(_:))

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(popUpButton)

        mainStack.insertArrangedSubview(row, at: 0)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            popUpButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            popUpButton.topAnchor.constraint(equalTo: row.topAnchor),
            popUpButton.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        presetPopUpButton = popUpButton
        reloadPresetMenu()
    }

    private func reloadPresetMenu() {
        guard let popUpButton = presetPopUpButton,
              let manager = AppDelegate.instance.presetManager
        else { return }

        let menu = NSMenu()
        let activeId = manager.activePreset?.id

        for preset in manager.presets {
            let item = NSMenuItem(title: preset.name, action: nil, keyEquivalent: "")
            item.representedObject = preset.id
            item.state = preset.id == activeId ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        addPresetActionItem(to: menu,
                            title: NSLocalizedString("New Preset from Defaults…", tableName: "Main", value: "", comment: ""),
                            action: .newFromDefaults)
        addPresetActionItem(to: menu,
                            title: NSLocalizedString("Duplicate Preset…", tableName: "Main", value: "", comment: ""),
                            action: .duplicate)
        addPresetActionItem(to: menu,
                            title: NSLocalizedString("Rename Preset…", tableName: "Main", value: "", comment: ""),
                            action: .rename)
        addPresetActionItem(to: menu,
                            title: NSLocalizedString("Delete Preset", tableName: "Main", value: "", comment: ""),
                            action: .delete)

        popUpButton.menu = menu

        if let activeId = activeId,
           let index = manager.presets.firstIndex(where: { $0.id == activeId }) {
            popUpButton.selectItem(at: index)
        }
    }

    private func addPresetActionItem(to menu: NSMenu, title: String, action: PresetMenuAction) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.tag = action.rawValue
        menu.addItem(item)
    }

    @objc private func presetSelectionChanged(_ sender: NSPopUpButton) {
        guard let manager = AppDelegate.instance.presetManager,
              let item = sender.selectedItem
        else { return }

        if let id = item.representedObject as? UUID {
            manager.activate(id)
        } else if let action = PresetMenuAction(rawValue: item.tag) {
            performPresetAction(action, with: manager)
        }

        reloadPresetMenu()
    }

    private func performPresetAction(_ action: PresetMenuAction, with manager: PresetManager) {
        switch action {
        case .newFromDefaults:
            let suggestion = NSLocalizedString("New Preset", tableName: "Main", value: "", comment: "")
            guard let name = promptForPresetName(question: NSLocalizedString("Name the new preset", tableName: "Main", value: "", comment: ""),
                                                 defaultValue: suggestion)
            else { return }
            let preset = manager.createFromDefaults(named: name)
            manager.activate(preset.id)

        case .duplicate:
            guard let active = manager.activePreset,
                  let name = promptForPresetName(question: NSLocalizedString("Name the duplicated preset", tableName: "Main", value: "", comment: ""),
                                                 defaultValue: active.name)
            else { return }
            if let copy = manager.duplicateActivePreset(named: name) {
                manager.activate(copy.id)
            }

        case .rename:
            guard let active = manager.activePreset,
                  let name = promptForPresetName(question: NSLocalizedString("Rename this preset", tableName: "Main", value: "", comment: ""),
                                                 defaultValue: active.name)
            else { return }
            manager.rename(active.id, to: name)

        case .delete:
            guard let active = manager.activePreset, manager.presets.count > 1 else { return }
            let response = AlertUtil.twoButtonAlert(
                question: NSLocalizedString("Delete this preset?", tableName: "Main", value: "", comment: ""),
                text: active.name,
                confirmText: NSLocalizedString("Delete", tableName: "Main", value: "", comment: ""),
                cancelText: NSLocalizedString("Cancel", tableName: "Main", value: "", comment: ""))
            guard response == .alertFirstButtonReturn else { return }
            manager.delete(active.id)
        }
    }

    private func promptForPresetName(question: String, defaultValue: String) -> String? {
        let entered = AlertUtil.textInputAlert(
            question: question,
            text: "",
            defaultValue: defaultValue,
            confirmText: NSLocalizedString("OK", tableName: "Main", value: "", comment: ""),
            cancelText: NSLocalizedString("Cancel", tableName: "Main", value: "", comment: ""))

        guard let entered = entered else { return nil }
        return PresetNaming.sanitized(entered)
    }

    private func subscribeToConfigImported() {
        Notification.Name.configImported.onPost { [weak self] _ in
            guard let self = self else { return }

            // Rebind every recorder so the tab reflects the newly applied keys.
            // setAssociatedUserDefaultsKey does not break the previous binding on
            // its own, so pass nil first to unbind.
            for (action, view) in self.actionsToViews {
                view.setAssociatedUserDefaultsKey(nil, withTransformerName: MASDictionaryTransformerName)
                view.setAssociatedUserDefaultsKey(action.name, withTransformerName: MASDictionaryTransformerName)
            }

            self.reloadPresetMenu()
        }
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
