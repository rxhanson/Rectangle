/// ShortcutsViewController.swift

import Cocoa
import MASShortcut
import SwiftUI

final class ShortcutItem: NSObject {
    let action: WindowAction

    init(_ action: WindowAction) {
        self.action = action
    }
}

final class SpacerItem: NSObject {}

final class ShortcutCategory: NSObject {
    let items: [ShortcutItem]

    init(actions: [WindowAction]) {
        self.items = actions.map { ShortcutItem($0) }
    }
}

final class CategoryGroup: NSObject {
    let title: String
    let items: [Any]
    let isCollapsible: Bool

    init(title: String, categories: [ShortcutCategory], subGroups: [CategoryGroup] = [], isCollapsible: Bool = true) {
        self.title = title
        self.isCollapsible = isCollapsible

        var flatItems: [Any] = []
        for (index, category) in categories.enumerated() {
            flatItems.append(contentsOf: category.items)

            // Add spacer after each category except the last inside the group (or if sub-groups follow)
            if index < categories.count - 1 || !subGroups.isEmpty {
                flatItems.append(SpacerItem())
            }
        }

        // Append child groups at the end of this group
        flatItems.append(contentsOf: subGroups)

        self.items = flatItems
    }
}

final class ShortcutSectionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ShortcutSectionCell")

    let titleLabel = NSTextField(labelWithString: "")
    var onTitleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Add gesture recognizer specifically to the title text label
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleTitleClick))
        titleLabel.addGestureRecognizer(clickGesture)
    }

    @objc private func handleTitleClick() {
        onTitleClick?()
    }

    func configure(title: String, onTitleClick: (() -> Void)? = nil) {
        titleLabel.stringValue = title
        self.onTitleClick = onTitleClick
    }
}

// MARK: - Action Button Configuration

struct ActionButtonConfig {
    let iconName: String
    let view: NSView
}

final class ShortcutActionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ShortcutActionCell")

    static var actionButtonConfigs: [WindowAction: ActionButtonConfig] = [
        .largerWidth: ActionButtonConfig(iconName: "gear", view: WidthSettingsView()),
        .tileRows: ActionButtonConfig(iconName: "gear", view: TileSettingsView())
    ]

    let iconImageView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let shortcutView = MASShortcutView()
    let popoverButton = PopoverButton()

    private var shortcutTrailingConstraint: NSLayoutConstraint?
    private var activePopover: NSPopover?
    private var currentConfig: ActionButtonConfig?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .right
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        shortcutView.translatesAutoresizingMaskIntoConstraints = false

        popoverButton.translatesAutoresizingMaskIntoConstraints = false
        popoverButton.bezelStyle = .inline
        popoverButton.isBordered = false
        popoverButton.contentTintColor = .secondaryLabelColor

        addSubview(titleLabel)
        addSubview(iconImageView)
        addSubview(shortcutView)
        addSubview(popoverButton)

        let trailingConstraint = shortcutView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -66)
        self.shortcutTrailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            trailingConstraint,
            shortcutView.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutView.widthAnchor.constraint(equalToConstant: 160),
            shortcutView.heightAnchor.constraint(equalToConstant: 19),

            popoverButton.leadingAnchor.constraint(equalTo: shortcutView.trailingAnchor, constant: 8),
            popoverButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            popoverButton.widthAnchor.constraint(equalToConstant: 20),
            popoverButton.heightAnchor.constraint(equalToConstant: 20),

            iconImageView.trailingAnchor.constraint(equalTo: shortcutView.leadingAnchor, constant: -16),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 21),
            iconImageView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.trailingAnchor.constraint(equalTo: iconImageView.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shortcutView.associatedUserDefaultsKey = nil
        activePopover?.close()
        activePopover = nil
        currentConfig = nil
    }

    func configure(with action: WindowAction, recordingObserver: ShortcutRecordingObserver) {
        iconImageView.image = action.image
        titleLabel.stringValue = action.settingsDisplayName ?? action.displayName ?? ""

        if Defaults.allowAnyShortcut.enabled {
            shortcutView.shortcutValidator = PassthroughShortcutValidator()
        } else {
            shortcutView.shortcutValidator = MASShortcutValidator()
        }

        shortcutView.associatedUserDefaultsKey = nil
        shortcutView.setAssociatedUserDefaultsKey(action.name, withTransformerName: MASDictionaryTransformerName)
        recordingObserver.observe([shortcutView])

        if let config = Self.actionButtonConfigs[action] {
            self.currentConfig = config
            popoverButton.image = NSImage(systemSymbolName: config.iconName, accessibilityDescription: "Information")
            popoverButton.contentView = config.view
            popoverButton.isHidden = false
        } else {
            self.currentConfig = nil
            popoverButton.isHidden = true
        }
    }
}

// MARK: - ShortcutsViewController

class ShortcutsViewController: NSViewController {

    private let initialSize = NSSize(width: 500, height: 610)
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let shortcutRecordingObserver = ShortcutRecordingObserver()
    private var allowAnyShortcutObserver: NSObjectProtocol?
    private var lastGroupToggleTime: TimeInterval = 0

    private var rootItems: [CategoryGroup] = []

    override func loadView() {
        setupGroups()
        let containerView = NSView(frame: NSRect(origin: .zero, size: initialSize))

        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: initialSize.width),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200) // Minimum height
        ])
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .none
        outlineView.rowHeight = 28
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.indentationPerLevel = 0
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ShortcutColumn"))
        column.resizingMask = .autoresizingMask
        column.width = 300
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = self
        outlineView.delegate = self

        scrollView.documentView = outlineView
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Expand non-collapsible groups on load
        for group in rootItems where !group.isCollapsible {
            outlineView.expandItem(group)
        }
        
        subscribeToAllowAnyShortcutToggle()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.setContentSize(initialSize)
    }
    
    private func setupGroups() {
        let standardCategories: [ShortcutCategory] = [
            ShortcutCategory(actions: [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf]),
            ShortcutCategory(actions: [.topLeft, .topRight, .bottomLeft, .bottomRight]),
            ShortcutCategory(actions: [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore]),
            ShortcutCategory(actions: [.nextDisplay, .previousDisplay])
        ]

        let moreCategories: [ShortcutCategory] = [
            ShortcutCategory(actions: [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
            ShortcutCategory(actions: [
                .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths, .lastThreeFourths
            ]),
            ShortcutCategory(actions: [
                .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth
            ]),
            ShortcutCategory(actions: [.moveLeft, .moveRight, .moveUp, .moveDown])
        ]

        let extraCategories: [ShortcutCategory] = [
            ShortcutCategory(actions: [.tileRows, .tileColumns]),
            ShortcutCategory(actions: [.largerWidth, .smallerWidth]),
            ShortcutCategory(actions: [.topVerticalThird, .middleVerticalThird, .bottomVerticalThird, .topVerticalTwoThirds, .bottomVerticalTwoThirds]),
            ShortcutCategory(actions: [.topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth, .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth]),
            ShortcutCategory(actions: [.topLeftNinth, .topLeftTwelfth, .topLeftSixteenth])
        ]

        let extraGroup = CategoryGroup(title: "Extra", categories: extraCategories, isCollapsible: true)

        let standardGroup = CategoryGroup(title: "", categories: standardCategories, isCollapsible: false)
        let moreGroup = CategoryGroup(title: "⋯", categories: moreCategories, subGroups: [extraGroup], isCollapsible: true)

        rootItems = [standardGroup, moreGroup]
    }
    
    deinit {
        if let observer = allowAnyShortcutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func subscribeToAllowAnyShortcutToggle() {
        allowAnyShortcutObserver = Notification.Name.allowAnyShortcut.onPost { [weak self] _ in
            guard let self = self else { return }
            self.outlineView.reloadData()
            self.outlineView.expandItem(nil, expandChildren: true)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension ShortcutsViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootItems.count
        }
        if let group = item as? CategoryGroup {
            return group.items.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is CategoryGroup
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootItems[index]
        }
        if let group = item as? CategoryGroup {
            return group.items[index]
        }
        fatalError("Unexpected outline view item: \(String(describing: item))")
    }
}

// MARK: - NSOutlineViewDelegate

extension ShortcutsViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? CategoryGroup {
            let cell = outlineView.makeView(withIdentifier: ShortcutSectionCellView.identifier, owner: self) as? ShortcutSectionCellView ?? ShortcutSectionCellView()
            cell.identifier = ShortcutSectionCellView.identifier
            
            cell.configure(title: group.title) { [weak self, weak group] in
                guard let self = self, let group = group, group.isCollapsible else { return }
                
                if self.outlineView.isItemExpanded(group) {
                    self.outlineView.animator().collapseItem(group)
                } else {
                    self.outlineView.animator().expandItem(group)
                }
            }
            return cell
        }

        if let shortcutItem = item as? ShortcutItem {
            let cell = outlineView.makeView(withIdentifier: ShortcutActionCellView.identifier, owner: self) as? ShortcutActionCellView ?? ShortcutActionCellView()
            cell.identifier = ShortcutActionCellView.identifier
            cell.configure(with: shortcutItem.action, recordingObserver: shortcutRecordingObserver)
            return cell
        }

        if item is SpacerItem {
            let spacerView = NSView()
            spacerView.translatesAutoresizingMaskIntoConstraints = false
            spacerView.heightAnchor.constraint(equalToConstant: 14).isActive = true
            return spacerView
        }

        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is SpacerItem {
            return 14
        }
        if let group = item as? CategoryGroup, !group.isCollapsible {
            return 10
        }
        return 28
    }

    // Hide disclosure triangle arrow for non-collapsible groups
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        if let group = item as? CategoryGroup, !group.isCollapsible {
            return false
        }
        return true
    }

    // Prevent collapsing if group is non-collapsible
    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        if let group = item as? CategoryGroup, !group.isCollapsible {
            return false
        }
        return true
    }

    // MARK: - NSOutlineViewDelegate Dynamic Sizing Fix

    func outlineViewItemDidExpand(_ notification: Notification) {
        scheduleScrollViewUpdate()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        scheduleScrollViewUpdate()
    }

    private func scheduleScrollViewUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let documentView = self.scrollView.documentView {
                documentView.frame.size.height = self.outlineView.intrinsicContentSize.height
            }
            
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }
}
