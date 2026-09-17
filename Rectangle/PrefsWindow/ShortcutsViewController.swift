/// ShortcutsViewController.swift

import Cocoa
import MASShortcut

final class ShortcutItem: NSObject {
    let action: WindowAction

    init(_ action: WindowAction) {
        self.action = action
    }
}

final class ShortcutSection: NSObject {
    let title: String
    let items: [ShortcutItem]

    init(title: String, actions: [WindowAction]) {
        self.title = title
        self.items = actions.map { ShortcutItem($0) }
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
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
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
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shortcutView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(shortcutView)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 21),
            iconImageView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            shortcutView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            shortcutView.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutView.widthAnchor.constraint(equalToConstant: 160),
            shortcutView.heightAnchor.constraint(equalToConstant: 19)
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

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let shortcutRecordingObserver = ShortcutRecordingObserver()
    private var allowAnyShortcutObserver: NSObjectProtocol?

    private let sections: [ShortcutSection] = [
        ShortcutSection(title: WindowActionCategory.halves.displayName, actions: [
            .leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf
        ]),
        ShortcutSection(title: WindowActionCategory.corners.displayName, actions: [
            .topLeft, .topRight, .bottomLeft, .bottomRight
        ]),
        ShortcutSection(title: WindowActionCategory.max.displayName, actions: [
            .maximize, .almostMaximize, .maximizeHeight, .center, .restore
        ]),
        ShortcutSection(title: WindowActionCategory.size.displayName, actions: [
            .larger, .smaller
        ]),
        ShortcutSection(title: WindowActionCategory.thirds.displayName, actions: [
            .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds
        ]),
        ShortcutSection(title: WindowActionCategory.move.displayName, actions: [
            .moveLeft, .moveRight, .moveUp, .moveDown
        ]),
        ShortcutSection(title: WindowActionCategory.fourths.displayName, actions: [
            .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths, .lastThreeFourths
        ]),
        ShortcutSection(title: WindowActionCategory.sixths.displayName, actions: [
            .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth
        ]),
        ShortcutSection(title: WindowActionCategory.display.displayName, actions: [
            .nextDisplay, .previousDisplay
        ])
    ]

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 500))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        outlineView.translatesAutoresizingMaskIntoConstraints = false
        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .none
        outlineView.rowHeight = 28
        outlineView.indentationPerLevel = 16
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ShortcutColumn"))
        column.resizingMask = .autoresizingMask
        column.width = 460
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = self
        outlineView.delegate = self

        scrollView.documentView = outlineView
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outlineView.expandItem(nil, expandChildren: true)
        subscribeToAllowAnyShortcutToggle()
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

extension ShortcutsViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return sections.count
        }
        if let section = item as? ShortcutSection {
            return section.items.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is ShortcutSection
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return sections[index]
        }
        if let section = item as? ShortcutSection {
            return section.items[index]
        }
        fatalError("Unexpected outline view item: \(String(describing: item))")
    }
}

extension ShortcutsViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let section = item as? ShortcutSection {
            let cell = outlineView.makeView(withIdentifier: ShortcutSectionCellView.identifier, owner: self) as? ShortcutSectionCellView ?? ShortcutSectionCellView()
            cell.identifier = ShortcutSectionCellView.identifier
            cell.configure(title: section.title)
            return cell
        }

        if let shortcutItem = item as? ShortcutItem {
            let cell = outlineView.makeView(withIdentifier: ShortcutActionCellView.identifier, owner: self) as? ShortcutActionCellView ?? ShortcutActionCellView()
            cell.identifier = ShortcutActionCellView.identifier
            cell.configure(with: shortcutItem.action, recordingObserver: shortcutRecordingObserver)
            return cell
        }

        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return false
    }
}
