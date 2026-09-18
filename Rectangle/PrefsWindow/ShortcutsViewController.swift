/// ShortcutsViewController.swift

import Cocoa
import MASShortcut

final class ShortcutItem: NSObject {
    let action: WindowAction

    init(_ action: WindowAction) {
        self.action = action
    }
}

final class SpacerItem: NSObject {}

final class ShortcutCategory: NSObject {
    let items: [Any]

    init(actions: [WindowAction], includeSpacer: Bool = true) {
        var categoryItems: [Any] = actions.map { ShortcutItem($0) }
        if includeSpacer {
            categoryItems.append(SpacerItem())
        }
        self.items = categoryItems
    }
}

final class ShortcutGroup: NSObject {
    let title: String
    let items: [Any]

    init(title: String, categories: [ShortcutCategory]) {
        self.title = title

        var flatItems: [Any] = []
        for (index, category) in categories.enumerated() {
            // Include action items
            flatItems.append(contentsOf: category.items.compactMap { $0 as? ShortcutItem })

            // Add spacer after each category except the last inside the group
            if index < categories.count - 1 {
                flatItems.append(SpacerItem())
            }
        }
        self.items = flatItems
    }
}

final class ShortcutSectionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ShortcutSectionCell")

    let titleLabel = NSTextField(labelWithString: "")

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
    }

    func configure(title: String) {
        titleLabel.stringValue = title
    }
}

final class ShortcutActionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ShortcutActionCell")

    let iconImageView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let shortcutView = MASShortcutView()

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

        addSubview(titleLabel)
        addSubview(iconImageView)
        addSubview(shortcutView)

        NSLayoutConstraint.activate([
            shortcutView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -56),
            shortcutView.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutView.widthAnchor.constraint(equalToConstant: 160),
            shortcutView.heightAnchor.constraint(equalToConstant: 19),

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
    }

    func configure(with action: WindowAction, recordingObserver: ShortcutRecordingObserver) {
        iconImageView.image = action.image
        titleLabel.stringValue = action.displayName ?? ""

        if Defaults.allowAnyShortcut.enabled {
            shortcutView.shortcutValidator = PassthroughShortcutValidator()
        } else {
            shortcutView.shortcutValidator = MASShortcutValidator()
        }

        shortcutView.associatedUserDefaultsKey = nil
        shortcutView.setAssociatedUserDefaultsKey(action.name, withTransformerName: MASDictionaryTransformerName)
        recordingObserver.observe([shortcutView])
    }
}

class ShortcutsViewController: NSViewController {

    private let initialSize = NSSize(width: 480, height: 610)
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let shortcutRecordingObserver = ShortcutRecordingObserver()
    private var allowAnyShortcutObserver: NSObjectProtocol?

    private var rootItems: [Any] = []

    override func loadView() {
        setupGroups()
        let containerView = NSView(frame: NSRect(origin: .zero, size: initialSize))

        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: initialSize.width),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200) // Minimum height allowed
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
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
            ShortcutCategory(actions: [.nextDisplay, .previousDisplay], includeSpacer: false)
        ]

        let moreCategories: [ShortcutCategory] = [
            ShortcutCategory(actions: [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
            ShortcutCategory(actions: [
                .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths, .lastThreeFourths
            ]),
            ShortcutCategory(actions: [
                .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth
            ]),
            ShortcutCategory(actions: [.moveLeft, .moveRight, .moveUp, .moveDown], includeSpacer: false),
        ]

        var items: [Any] = []
        for category in standardCategories {
            items.append(contentsOf: category.items)
        }

        let moreGroup = ShortcutGroup(title: "More", categories: moreCategories)
        items.append(moreGroup)

        rootItems = items
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
        if let group = item as? ShortcutGroup {
            return group.items.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is ShortcutGroup
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootItems[index]
        }
        if let group = item as? ShortcutGroup {
            return group.items[index]
        }
        fatalError("Unexpected outline view item: \(String(describing: item))")
    }
}

// MARK: - NSOutlineViewDelegate

extension ShortcutsViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? ShortcutGroup {
            let cell = outlineView.makeView(withIdentifier: ShortcutSectionCellView.identifier, owner: self) as? ShortcutSectionCellView ?? ShortcutSectionCellView()
            cell.identifier = ShortcutSectionCellView.identifier
            cell.configure(title: group.title)
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
        return 28
    }
    
    // MARK: - NSOutlineViewDelegate Dynamic Sizing Fix

    func outlineViewItemDidExpand(_ notification: Notification) {
        scheduleScrollViewUpdate()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        scheduleScrollViewUpdate()
    }

    private func scheduleScrollViewUpdate() {
        // Defer execution until NSOutlineView completes its internal row animation and index updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Recalculate document frame height safely after row changes have finalized
            if let documentView = self.scrollView.documentView {
                documentView.frame.size.height = self.outlineView.intrinsicContentSize.height
            }
            
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }
}
