import Cocoa

enum LayoutHelperAppearance {
    static let cornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 10
    static let outline = NSColor(calibratedWhite: 0.76, alpha: 1)
    static let selection = NSColor(calibratedWhite: 0.62, alpha: 1)

    private static let cardCurve: (points: [CGPoint], tangents: [CGPoint], chords: [CGFloat]) = {
        let segments = 6
        let exponent: CGFloat = 2 / 2.1
        let points = (0...segments).map { index -> CGPoint in
            if index == 0 { return CGPoint(x: 0, y: 1) }
            if index == segments { return CGPoint(x: 1, y: 0) }
            let angle = CGFloat(index) * .pi / (2 * CGFloat(segments))
            return CGPoint(x: pow(sin(angle), exponent), y: pow(cos(angle), exponent))
        }
        let tangents = (0...segments).map { index -> CGPoint in
            if index == 0 { return CGPoint(x: 1, y: 0) }
            if index == segments { return CGPoint(x: 0, y: -1) }
            let angle = CGFloat(index) * .pi / (2 * CGFloat(segments))
            let x = pow(sin(angle), exponent - 1) * cos(angle)
            let y = -pow(cos(angle), exponent - 1) * sin(angle)
            let length = sqrt(x * x + y * y)
            return CGPoint(x: x / length, y: y / length)
        }
        let chords = (0..<segments).map { index -> CGFloat in
            let dx = points[index + 1].x - points[index].x
            let dy = points[index + 1].y - points[index].y
            return sqrt(dx * dx + dy * dy)
        }
        return (points, tangents, chords)
    }()

    static func cardPath(in rect: CGRect, radius: CGFloat = cardCornerRadius) -> CGPath {
        let radius = max(0, min(radius, min(rect.width, rect.height) / 2))
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        let (points, tangents, chords) = cardCurve
        let segments = chords.count
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))

        func corner(center: CGPoint, rotation: Int) {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let rotated: (CGFloat, CGFloat)
                switch rotation {
                case 1: rotated = (y, -x)
                case 2: rotated = (-x, -y)
                case 3: rotated = (-y, x)
                default: rotated = (x, y)
                }
                return CGPoint(x: center.x + rotated.0 * radius,
                               y: center.y + rotated.1 * radius)
            }
            for index in 0..<segments {
                let start = points[index]
                let end = points[index + 1]
                let startHandle = (index == 0 ? chords[0] : min(chords[index - 1], chords[index])) / 3
                let endHandle = (index == segments - 1 ? chords[index] : min(chords[index], chords[index + 1])) / 3
                path.addCurve(
                    to: point(end.x, end.y),
                    control1: point(start.x + tangents[index].x * startHandle,
                                    start.y + tangents[index].y * startHandle),
                    control2: point(end.x - tangents[index + 1].x * endHandle,
                                    end.y - tangents[index + 1].y * endHandle)
                )
            }
        }

        corner(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), rotation: 0)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        corner(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), rotation: 1)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        corner(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), rotation: 2)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        corner(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), rotation: 3)
        path.closeSubpath()
        return path
    }
}

struct LayoutHelperPreviewLayout {
    static let titleHeight: CGFloat = 40
    static let fallbackCardSize = CGSize(width: 200, height: 150)
    struct Result {
        let frames: [CGRect]
        let height: CGFloat
    }

    static func inset(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) / 8, min(size.width, size.height) < 320 ? 8 : 12)
    }

    static func sourceSize(for imageSize: CGSize?, fallback: CGSize) -> CGSize {
        guard let imageSize, imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return fallback }
        // Use the screenshot's aspect ratio without making Retina captures larger cards.
        let extent = max(fallback.width, fallback.height)
        let scale = extent / max(imageSize.width, imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func cardFrame(for imageSize: CGSize?, in slot: CGRect, isMinimized: Bool = false) -> CGRect {
        guard let imageSize, imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              slot.width > 0, slot.height > titleHeight else { return slot }
        let fittedScale = min(slot.width / imageSize.width, (slot.height - titleHeight) / imageSize.height)
        // Width floors belong to the arrangement, which reserves both dimensions.
        // A preview must always fit until its updated aspect has been arranged.
        let scale = fittedScale
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale + titleHeight)
        return CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func arrange(sizes: [CGSize], in viewport: CGSize, compact: Bool = false,
                        expandedCards: [Bool] = []) -> Result {
        let width = max(1, viewport.width)
        let height = max(1, viewport.height)
        let gap: CGFloat = 16
        let sources = sizes.map { raw in
            raw.width.isFinite && raw.height.isFinite && raw.width > 0 && raw.height > 0
                ? raw : CGSize(width: 800, height: 500)
        }
        let floors = sources.indices.map { index -> CGSize in
            guard expandedCards.indices.contains(index), expandedCards[index] else { return .zero }
            let minimumWidth = min(fallbackCardSize.width, width)
            return CGSize(width: minimumWidth, height: compact ? fallbackCardSize.height - titleHeight
                          : minimumWidth * sources[index].height / sources[index].width)
        }
        let bases = sources.enumerated().map { index, source -> CGSize in
            let floor = floors[index]
            if compact { return CGSize(width: max(floor.width, min(180, width)), height: max(floor.height, 100)) }
            // Shared 36% scale, a readability floor for tiny windows, and a cap
            // prevent a huge source window from taking over the chooser.
            let scale = min(max(0.36, 120 / max(source.width, source.height)),
                            min(420, width) / source.width, 260 / source.height)
            return CGSize(width: max(floor.width, source.width * scale),
                          height: max(floor.height, source.height * scale))
        }
        func pack(_ scale: CGFloat) -> Result {
            var rows: [[CGSize]] = []
            var row: [CGSize] = []
            var used: CGFloat = 0
            for (index, base) in bases.enumerated() {
                let cardWidth = max(floors[index].width, base.width * scale)
                let imageHeight = compact ? max(floors[index].height, base.height * scale)
                    : cardWidth * base.height / base.width
                let size = CGSize(width: cardWidth, height: imageHeight + titleHeight)
                if !row.isEmpty && used + gap + size.width > width {
                    rows.append(row); row = []; used = 0
                }
                used += (row.isEmpty ? 0 : gap) + size.width
                row.append(size)
            }
            if !row.isEmpty { rows.append(row) }
            let rowHeights = rows.map { $0.map(\.height).max() ?? 0 }
            let total = rowHeights.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * gap
            var y = max(0, (height - total) / 2)
            var frames: [CGRect] = []
            for (index, row) in rows.enumerated() {
                let rowWidth = row.map(\.width).reduce(0, +) + CGFloat(row.count - 1) * gap
                var x = (width - rowWidth) / 2
                for size in row {
                    frames.append(CGRect(x: x, y: y + (rowHeights[index] - size.height) / 2,
                                         width: size.width, height: size.height))
                    x += size.width + gap
                }
                y += rowHeights[index] + gap
            }
            return Result(frames: frames, height: max(height, total))
        }
        // Stop shrinking at 60%, retaining the fallback-card floor. Overflow
        // scrolls instead of truncating short titles without a preview.
        for scale in [CGFloat(1), 0.9, 0.8, 0.7] {
            let result = pack(scale)
            if result.height <= height { return result }
        }
        return pack(0.6)
    }
}

/// A full-region input surface with a visually inset blur. Transparent margins
/// still belong to this window, so dismissal never clicks through to another app.
class LayoutHelperSurface: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .moveToActiveSpace]
        title = "Layout Helper"
        setAccessibilityLabel("Layout Helper")
    }

    @discardableResult func prepare(in frame: CGRect, drawsBackground: Bool = true) -> NSView {
        setFrame(frame, display: false)
        let root = LayoutHelperDocument(frame: CGRect(origin: .zero, size: frame.size))
        let inset = LayoutHelperPreviewLayout.inset(for: frame.size)
        let blur = LayoutHelperBlurView(frame: root.bounds.insetBy(dx: inset, dy: inset),
                                   cornerRadius: LayoutHelperAppearance.cornerRadius, flipped: true)
        if drawsBackground {
            let shadow = LayoutHelperShadow(frame: blur.frame, radius: min(12, inset))
            root.addSubview(shadow)
            root.addSubview(blur)

        }
        let foreground: NSView
        if drawsBackground {
            foreground = blur.content
        } else {
            foreground = LayoutHelperDocument(frame: blur.frame)
            root.addSubview(foreground)
        }
        contentView = root
        return foreground
    }

    /// Disabled cards remain controls; clicking one must not dismiss the picker.
    func isBackground(at point: NSPoint) -> Bool {
        var hit = contentView?.hitTest(point)
        while let view = hit {
            if view is NSControl { return false }
            hit = view.superview
        }
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { onDismiss?(); return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if isBackground(at: event.locationInWindow) { onDismiss?(); return }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

final class LayoutHelperPanel: LayoutHelperSurface {
    struct Item {
        let id: CGWindowID
        let title: String
        let icon: NSImage?
        let unavailableReason: String?
        var sourceSize: CGSize = CGSize(width: 800, height: 500)
        var isCurrentWindow = false
        var previewKey: LayoutHelperPreviewKey?
        var isMinimized = false
    }

    var onSelect: ((CGWindowID) -> Void)?
    var onPermission: (() -> Void)?
    var onVisiblePreviewsChanged: (() -> Void)?
    private(set) var keyboardSelection = false
    private var scrollObserver: NSObjectProtocol?
    private var visibleIDs: [CGWindowID] = []
    var visiblePreviewIDs: [CGWindowID] {
        cards.filter { $0.superview?.visibleRect.intersects($0.frame) == true }.map { $0.item.id }
    }
    private var cards: [LayoutHelperCard] = []
    private var candidateIDs: [CGWindowID] = []
    private var footerControls: [NSView] = []
    private var scrollView: NSScrollView?
    private var showingPermission = false
    private var waitsForPreviews = false
    private var shownMessage: String?
    private var backdrops: [LayoutHelperSurface] = []
    private var regionEntranceOffset: CGPoint?
    var hasActiveSession: Bool { !backdrops.isEmpty }
    override var canBecomeKey: Bool { true }

    func owns(_ window: NSWindow?) -> Bool {
        window === self || backdrops.contains { $0 === window }
    }

    func containsPointerEvent(_ event: NSEvent) -> Bool {
        let point = event.cgEvent?.location.screenFlipped ?? NSEvent.mouseLocation
        return isVisible && (owns(event.window) || frame.contains(point)
            || backdrops.contains { $0.frame.contains(point) })
    }

    func show(in frame: CGRect, items: [Item], offerPermission: Bool, message: String? = nil,
              remainingRegions: [CGRect] = [], keyboardTriggered: Bool = false, images: [CGWindowID: NSImage] = [:], waitForPreviews: Bool = false) {
        if hasActiveSession {
            if self.frame != frame {
                regionEntranceOffset = Self.regionSlideOffset(from: self.frame, to: frame)
            } else if !isVisible {
                regionEntranceOffset = .zero
            }
        } else {
            regionEntranceOffset = nil
        }
        reconcileBackdrops(for: [frame] + remainingRegions)
        var images = offerPermission ? [:] : images
        for card in cards where !offerPermission && images[card.item.id] == nil {
            if let item = items.first(where: { $0.id == card.item.id }),
               item.previewKey == card.item.previewKey, item.sourceSize == card.item.sourceSize,
               let image = card.preview { images[item.id] = image }
        }
        if isVisible, self.frame == frame, showingPermission == offerPermission, shownMessage == message,
           candidateIDs == items.map(\.id) {
            let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            var geometryChanged = false
            for card in cards {
                guard let item = itemsByID[card.item.id] else { continue }
                geometryChanged = geometryChanged || card.item.sourceSize != item.sourceSize || card.item.isMinimized != item.isMinimized
                // Reuse cards as catalog details arrive, but discard previews when
                // the window identity or dimensions change.
                if offerPermission || card.item.previewKey != item.previewKey || card.item.sourceSize != item.sourceSize {
                    card.preview = nil
                }
                card.state = .off
                card.item = item
                if let image = images[item.id] { updateImage(image, for: item.id) }
            }
            if geometryChanged { arrangeUpdatedPreviews() }
            updateKeyViews()
            if keyboardSelection, let focused = firstResponder as? LayoutHelperCard, !focused.isEnabled {
                makeFirstResponder(cards.first(where: { $0.isEnabled && !$0.isHidden }))
            }
            return
        }
        let existingIDs = isVisible && self.frame == frame ? Set(cards.map { $0.item.id }) : []
        let focusedID = existingIDs.isEmpty ? nil : (firstResponder as? LayoutHelperCard)?.item.id
        let scrollPosition = existingIDs.isEmpty ? nil : scrollView?.contentView.bounds.origin
        configure(in: frame, items: items, offerPermission: offerPermission, message: message,
                  keyboardTriggered: keyboardTriggered, images: images, waitForPreviews: waitForPreviews,
                  separateBackground: true)
        makeFirstResponder(keyboardSelection
            ? cards.first(where: { $0.item.id == focusedID && $0.isEnabled }) ?? initialFirstResponder
            : contentView)
        if let scrollPosition, let scrollView {
            scrollView.contentView.scroll(to: scrollPosition)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        contentView?.layoutSubtreeIfNeeded()
        // Render the cached thumbnails before committing the entrance, so a
        // freshly created layer does not spend its first frames empty.
        displayIfNeeded()
        animatePresentation(excluding: existingIDs)
        makeKeyAndOrderFront(nil)
    }

    static func regionSlideOffset(from previous: CGRect, to next: CGRect) -> CGPoint {
        // Screen coordinates increase upwards; card layers are flipped.
        let dx = previous.midX - next.midX
        let dy = next.midY - previous.midY
        let distance = hypot(dx, dy)
        guard distance > 0 else { return .zero }
        return CGPoint(x: dx / distance * 8, y: dy / distance * 8)
    }

    private func reconcileBackdrops(for regions: [CGRect]) {
        for backdrop in backdrops where !regions.contains(backdrop.frame) { backdrop.orderOut(nil) }
        backdrops = regions.map { region in
            let backdrop: LayoutHelperSurface
            if let existing = backdrops.first(where: { $0.frame == region }) {
                backdrop = existing
            } else {
                backdrop = LayoutHelperSurface()
                backdrop.onDismiss = { [weak self] in self?.onDismiss?() }
                backdrop.prepare(in: region)
            }
            if !backdrop.isVisible { backdrop.orderFront(nil) }
            return backdrop
        }
    }

    func beginPlacement() {
        finishPresentation()
        orderOut(nil)
        backdrops.first(where: { $0.frame == frame })?.orderOut(nil)
    }

    /// Configure without displaying or activating the panel.
    func configure(in frame: CGRect, items: [Item], offerPermission: Bool, message: String? = nil,
                   keyboardTriggered: Bool = false, images: [CGWindowID: NSImage] = [:], waitForPreviews: Bool = false,
                   separateBackground: Bool = false) {
        finishPresentation()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        keyboardSelection = keyboardTriggered
        showingPermission = offerPermission
        let images = offerPermission ? [:] : images
        waitsForPreviews = waitForPreviews && !offerPermission
        shownMessage = message
        let surface = prepare(in: frame, drawsBackground: !separateBackground)
        let width = surface.bounds.width
        let height = surface.bounds.height
        let close = LayoutHelperCloseButton(title: "×", target: self, action: #selector(dismissPicker))
        close.isBordered = false
        close.wantsLayer = true
        close.font = .systemFont(ofSize: 22, weight: .regular)
        let showClose = Defaults.layoutHelperCloseButton.enabled
        let closeRadius: CGFloat = 15
        let closeCenter = CGPoint(x: width - LayoutHelperAppearance.cornerRadius,
                                  y: LayoutHelperAppearance.cornerRadius)
        let closeSurface = LayoutHelperBlurView(frame: NSRect(x: closeCenter.x - closeRadius,
                                                        y: closeCenter.y - closeRadius, width: 30, height: 30),
                                           material: .popover, cornerRadius: 15, flipped: true)
        closeSurface.blendingMode = .withinWindow
        close.frame = closeSurface.content.bounds
        close.autoresizingMask = [.width, .height]
        closeSurface.content.addSubview(close)
        close.setAccessibilityLabel("Dismiss Layout Helper")
        close.toolTip = "Dismiss (Escape)"

        let top: CGFloat = message == nil ? 44 : 84
        let bottom: CGFloat = 24
        let horizontal: CGFloat = min(24, width / 8)
        let footerHeight: CGFloat = offerPermission ? 48 : 0
        var footerControls: [NSView] = []
        if offerPermission {
            let permission = LayoutHelperPermissionButton(target: self, action: #selector(requestPermission))
            let buttonWidth = min(156, max(1, width - 40))
            permission.frame = NSRect(x: (width - buttonWidth) / 2, y: max(0, height - 40), width: buttonWidth, height: 28)
            permission.toolTip = "Window previews need Screen Recording access. Icons and titles still work."
            surface.addSubview(permission)
            footerControls.append(permission)
        }
        // The viewport spans the surface; content margins scroll with the cards.
        // Shadows may extend into those margins without an inner clipping edge.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: max(1, height - footerHeight)))
        scrollView = scroll
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerInsets = NSEdgeInsets(top: LayoutHelperAppearance.cornerRadius, left: 0,
                                             bottom: LayoutHelperAppearance.cornerRadius, right: 4)
        scroll.autohidesScrollers = true
        let document = LayoutHelperDocument()
        scroll.documentView = document
        surface.addSubview(scroll)
        if showClose { surface.addSubview(closeSurface, positioned: .above, relativeTo: scroll) }
        if let message {
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 12)
            label.frame = NSRect(x: horizontal, y: 44, width: max(1, width - horizontal * 2), height: 36)
            document.addSubview(label)
        }

        candidateIDs = items.map(\.id)
        let orderedItems = waitsForPreviews
            ? items.filter { images[$0.id] != nil } + items.filter { images[$0.id] == nil }
            : items
        let sizes = orderedItems.map { item in
            let imageSize = images[item.id]?.size
            let sourceAspect = item.sourceSize.width / max(1, item.sourceSize.height)
            let imageAspect = (imageSize?.width ?? item.sourceSize.width) / max(1, imageSize?.height ?? item.sourceSize.height)
            let staleAspect = item.isMinimized && abs(imageAspect - sourceAspect) > max(sourceAspect, imageAspect) * 0.005
            return LayoutHelperPreviewLayout.sourceSize(for: staleAspect ? nil : imageSize, fallback: item.sourceSize)
        }
        let arrangement = LayoutHelperPreviewLayout.arrange(sizes: sizes, in: CGSize(width: max(1, scroll.contentSize.width - horizontal * 2),
                                                                 height: max(1, scroll.contentSize.height - top - bottom)), compact: offerPermission,
                                                              expandedCards: orderedItems.map { $0.isMinimized || images[$0.id] == nil })
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: top + arrangement.height + bottom)
        cards = zip(orderedItems, arrangement.frames).map { item, frame in
            let card = LayoutHelperCard(item: item)
            card.layoutSlot = frame.offsetBy(dx: horizontal, dy: top)
            card.preview = images[item.id]
            card.isHidden = waitsForPreviews && card.preview == nil
            card.target = self
            card.action = #selector(selectCard(_:))
            document.addSubview(card)
            return card
        }
        // Keyboard traversal follows display order as previews become ready.
        self.footerControls = footerControls + (showClose ? [close] : [])
        updateKeyViews()
        let fallback: NSView? = showClose ? close : contentView
        initialFirstResponder = keyboardSelection ? cards.first(where: { $0.isEnabled && !$0.isHidden }) ?? fallback : contentView
        scroll.contentView.postsBoundsChangedNotifications = true
        visibleIDs = visiblePreviewIDs
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.finishPresentation()
                let ids = self.visiblePreviewIDs
                if ids != self.visibleIDs { self.visibleIDs = ids; self.onVisiblePreviewsChanged?() }
            }
    }

    private func updateKeyViews() {
        let controls: [NSView] = cards.filter { $0.isEnabled && !$0.isHidden } + footerControls
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
    }

    func updateImage(_ image: NSImage, for id: CGWindowID) {
        guard !showingPermission, let card = cards.first(where: { $0.item.id == id }) else { return }
        let previousSize = card.preview?.size ?? card.item.sourceSize
        card.preview = image
        let oldAspect = previousSize.width / max(1, previousSize.height)
        let newAspect = image.size.width / max(1, image.size.height)
        if abs(newAspect - oldAspect) > max(oldAspect, newAspect) * 0.000001 { arrangeUpdatedPreviews() }
        reveal(card)
    }

    func updateImages(_ images: [CGWindowID: NSImage]) {
        for card in cards {
            if let image = images[card.item.id] { updateImage(image, for: card.item.id) }
        }
        WindowAnimationDiagnostics.event("helper-preview-delivery", fields: ["count": images.count])
    }

    func previewFailed(for id: CGWindowID) {
        guard let card = cards.first(where: { $0.item.id == id }) else { return }
        if card.preview == nil { card.previewUnavailable = true }
        reveal(card)
    }

    private func arrangeUpdatedPreviews() {
        guard let scroll = scrollView, let document = scroll.documentView else { return }
        finishPresentation()
        let top: CGFloat = shownMessage == nil ? 44 : 84
        let bottom: CGFloat = 24
        let horizontal: CGFloat = min(24, scroll.frame.width / 8)
        let sizes = cards.map { LayoutHelperPreviewLayout.sourceSize(for: $0.preview?.size, fallback: $0.item.sourceSize) }
        let arrangement = LayoutHelperPreviewLayout.arrange(sizes: sizes,
            in: CGSize(width: max(1, scroll.contentSize.width - horizontal * 2),
                       height: max(1, scroll.contentSize.height - top - bottom)),
            expandedCards: cards.map { $0.item.isMinimized || $0.preview == nil })
        let origin = scroll.contentView.bounds.origin
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: top + arrangement.height + bottom))
        for (card, frame) in zip(cards, arrangement.frames) {
            card.layoutSlot = frame.offsetBy(dx: horizontal, dy: top)
        }
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(
            CGRect(origin: origin, size: scroll.contentView.bounds.size)).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
        visibleIDs = visiblePreviewIDs
        onVisiblePreviewsChanged?()
    }

    private func reveal(_ card: LayoutHelperCard) {
        guard card.isHidden else { return }
        // Reveal the card in its own slot. Swapping slots on completion
        // can place a portrait preview in a shorter landscape row.
        card.isHidden = false
        card.layoutSubtreeIfNeeded()
        card.displayIfNeeded()
        animatePresentation(excluding: Set(cards.filter { $0 !== card }.map { $0.item.id }), preserveExisting: true)
        updateKeyViews()
        if keyboardSelection, !(firstResponder is LayoutHelperCard),
           firstResponder === initialFirstResponder,
           let visible = cards.first(where: { !$0.isHidden && $0.isEnabled
               && $0.superview?.visibleRect.intersects($0.frame) == true }) {
            // Automatic focus must not scroll even a tall, partly visible card.
            let origin = scrollView?.contentView.bounds.origin
            makeFirstResponder(visible)
            if let origin, let scroll = scrollView {
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        visibleIDs = visiblePreviewIDs
    }

    func showSelection(inProgress id: CGWindowID) {
        if let card = cards.first(where: { $0.item.id == id }) {
            card.state = .on
            card.needsDisplay = true
        }
    }

    /// Each visible card settles independently while layout and hit testing
    /// retain their final geometry. Input can finish every entrance immediately.
    func animatePresentation(excluding existingIDs: Set<CGWindowID> = [],
                             reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                             preserveExisting: Bool = false) {
        if !preserveExisting { finishPresentation() }
        let entering = cards.filter {
            !$0.isHidden && !existingIDs.contains($0.item.id) && $0.superview?.visibleRect.intersects($0.frame) == true
        }
        let largest = entering.map { sqrt($0.frame.width * $0.frame.height) }.max() ?? 1
        let stagger = min(0.028, 0.1 / Double(max(1, entering.count - 1)))
        let start = CACurrentMediaTime()
        for (index, card) in entering.enumerated() {
            guard let layer = card.layer else { continue }
            if let offset = regionEntranceOffset {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.12
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                var animations: [CAAnimation] = [fade]
                if !reduceMotion && !preserveExisting {
                    let slide = CABasicAnimation(keyPath: "transform")
                    slide.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(offset.x, offset.y, 0))
                    slide.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                    slide.duration = 0.12
                    slide.timingFunction = fade.timingFunction
                    animations.append(slide)
                }
                let entrance = CAAnimationGroup()
                entrance.animations = animations
                entrance.duration = 0.12
                entrance.beginTime = layer.convertTime(start, from: nil)
                layer.add(entrance, forKey: "layoutHelperEntrance")
                continue
            }
            let weight = min(1, sqrt(card.frame.width * card.frame.height) / max(1, largest))
            let cadence = CGFloat(index % 3) / 2
            let duration = reduceMotion ? 0.083 : 0.24 + Double(weight) * 0.055 + Double(cadence) * 0.025
            let delay = reduceMotion ? 0 : Double(index) * stagger
            var animations: [CAAnimation] = []
            if !reduceMotion {
                let scale: CGFloat = 0.96
                let anchor = CGPoint(x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
                                     y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)
                var transform = CATransform3DMakeScale(scale, scale, 1)
                transform.m41 = (anchor.x - layer.bounds.midX) * (scale - 1)
                transform.m42 = (anchor.y - layer.bounds.midY) * (scale - 1) - (12 + weight * 8 + cadence * 2)
                let settle = CABasicAnimation(keyPath: "transform")
                settle.fromValue = NSValue(caTransform3D: transform)
                settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                settle.duration = duration
                settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.25, 1)
                animations.append(settle)
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = reduceMotion ? duration : 0.1
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animations.append(fade)
            let entrance = CAAnimationGroup()
            entrance.animations = animations
            entrance.duration = duration
            entrance.beginTime = layer.convertTime(start + delay, from: nil)
            // Hold the initial appearance during the stagger without timers or
            // delayed callbacks that could outlive this panel.
            entrance.fillMode = .backwards
            layer.add(entrance, forKey: "layoutHelperEntrance")
        }
    }

    private func finishPresentation() {
        for card in cards {
            card.layer?.removeAnimation(forKey: "layoutHelperEntrance")
            card.layer?.removeAnimation(forKey: "layoutHelperEntranceOpacity")
        }
    }

    func dismiss() {
        finishPresentation()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        orderOut(nil)
        backdrops.forEach { $0.orderOut(nil) }
        backdrops.removeAll()
        regionEntranceOffset = nil
        cards.removeAll()
        footerControls.removeAll()
        contentView = nil
    }

    override func sendEvent(_ event: NSEvent) {
        // Resolve visual and hit-test positions immediately for early input.
        // No completion callbacks can reopen a dismissed or replaced panel.
        if [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel].contains(event.type) {
            finishPresentation()
        }
        if event.type == .leftMouseDown { setKeyboardSelection(false) }
        if event.type == .keyDown, [48, 123, 124, 125, 126, 36, 76, 49].contains(event.keyCode) {
            let enteringKeyboardSelection = !keyboardSelection
            setKeyboardSelection(true)
            if enteringKeyboardSelection, let first = cards.first(where: { $0.isEnabled && !$0.isHidden }) {
                makeFirstResponder(first)
                first.scrollToVisible(first.bounds)
                // The first navigation key reveals the first selection; it must
                // not also advance a responder left over from pointer input.
                if [48, 123, 124, 125, 126].contains(event.keyCode) { return }
            }
            if [123, 124, 125, 126].contains(event.keyCode) {
                moveSelection(keyCode: event.keyCode)
                return
            }
            if [36, 76, 49].contains(event.keyCode), let card = firstResponder as? LayoutHelperCard {
                card.performClick(nil)
                return
            }
        }
        super.sendEvent(event)
    }

    private func setKeyboardSelection(_ enabled: Bool) {
        keyboardSelection = enabled
        if !enabled { makeFirstResponder(contentView) }
        cards.forEach { $0.needsDisplay = true }
    }

    private func moveSelection(keyCode: UInt16) {
        let eligible = cards.filter { $0.isEnabled && !$0.isHidden }
        guard !eligible.isEmpty else { return }
        let current = firstResponder as? LayoutHelperCard
        var destination: LayoutHelperCard?
        if let current, let index = eligible.firstIndex(of: current) {
            if keyCode == 123 || keyCode == 124 {
                let delta = keyCode == 123 ? -1 : 1
                destination = eligible[(index + delta + eligible.count) % eligible.count]
            } else {
                let down = keyCode == 125
                destination = eligible.filter { down ? $0.frame.midY > current.frame.midY + 1 : $0.frame.midY < current.frame.midY - 1 }
                    .min { a, b in
                        let aDistance = abs(a.frame.midY - current.frame.midY) * 2 + abs(a.frame.midX - current.frame.midX)
                        let bDistance = abs(b.frame.midY - current.frame.midY) * 2 + abs(b.frame.midX - current.frame.midX)
                        return aDistance < bDistance
                    }
            }
        }
        if let destination = destination ?? current ?? eligible.first {
            makeFirstResponder(destination)
            destination.scrollToVisible(destination.bounds)
        }
    }

    @objc private func dismissPicker() { onDismiss?() }
    @objc private func requestPermission() { onPermission?() }
    @objc private func selectCard(_ sender: LayoutHelperCard) { onSelect?(sender.item.id) }
}

private final class LayoutHelperCloseButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: center.x - 4.5, y: center.y - 4.5))
        cross.line(to: CGPoint(x: center.x + 4.5, y: center.y + 4.5))
        cross.move(to: CGPoint(x: center.x - 4.5, y: center.y + 4.5))
        cross.line(to: CGPoint(x: center.x + 4.5, y: center.y - 4.5))
        cross.lineWidth = 2
        cross.lineCapStyle = .round
        (isHighlighted ? NSColor.secondaryLabelColor : NSColor.labelColor).setStroke()
        cross.stroke()
    }
}

private final class LayoutHelperShadow: NSView {
    override var isFlipped: Bool { true }

    init(frame: CGRect, radius: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = radius
        layer?.shadowOffset = .zero
        layer?.shadowPath = CGPath(roundedRect: bounds,
                                   cornerWidth: LayoutHelperAppearance.cornerRadius,
                                   cornerHeight: LayoutHelperAppearance.cornerRadius,
                                   transform: nil)
        updateShadowOpacity()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateShadowOpacity()
    }

    private func updateShadowOpacity() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.shadowOpacity = FootprintStyle.shadowOpacity(isDark: dark) / 2
    }
}

private final class LayoutHelperDocument: NSView {
    override var isFlipped: Bool { true }
    // Keep pointer sessions neutral without AppKit focusing the close button.
    override var acceptsFirstResponder: Bool { window?.contentView === self }
}

/// Screenshot transitions have their own backing layer, below the fixed card chrome.
private final class LayoutHelperPreviewContent: NSView {
    private(set) var preview: NSImage?
    var icon: NSImage?
    var isMinimized = false
    private var imageIdentity: CGImage?
    private var previewBackground: NSColor?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setPreview(_ image: NSImage?, animated: Bool) {
        let identity = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if preview === image || (identity != nil && identity === imageIdentity) { return }
        preview = image
        imageIdentity = identity
        previewBackground = nil
        if let identity {
            let bitmap = NSBitmapImageRep(cgImage: identity)
            // Captured windows keep transparent rounded corners. Extend the
            // top edge's color underneath them so they join the card header.
            for row in 0..<min(8, bitmap.pixelsHigh) {
                if let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: row), color.alphaComponent >= 0.99 {
                    previewBackground = color
                    break
                }
            }
        }
        if image == nil || !animated {
            layer?.removeAnimation(forKey: kCATransition)
        } else if layer?.animation(forKey: kCATransition) == nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.12
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(fade, forKey: kCATransition)
        }
        // An update during a fade replaces its destination without queuing or
        // extending the transition. Re-delivering a cached image does nothing.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let card = superview else { return }
        let cardBounds = card.bounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(cgPath: LayoutHelperAppearance.cardPath(in: cardBounds)).addClip()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (previewBackground ?? NSColor(srgbRed: dark ? 0.12 : 1, green: dark ? 0.12 : 1, blue: dark ? 0.12 : 1, alpha: 1)).setFill()
        bounds.fill()
        if let image = preview ?? icon, image.size.width > 0, image.size.height > 0 {
            let cap: CGFloat = preview == nil ? 64 / max(image.size.width, image.size.height) : .greatestFiniteMagnitude
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height, cap)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 - (preview == nil && isMinimized ? 20 : 0),
                                 width: size.width, height: size.height), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class LayoutHelperCardForeground: NSView {
    weak var card: LayoutHelperCard?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { card?.drawForeground() }
}

private final class LayoutHelperCard: NSButton {
    private let artwork = LayoutHelperPreviewContent()
    private let foreground = LayoutHelperCardForeground()
    var item: LayoutHelperPanel.Item {
        didSet {
            title = item.title
            isEnabled = item.unavailableReason == nil
            updateAccessibilityStatus()
            artwork.icon = item.icon
            artwork.isMinimized = item.isMinimized
            artwork.needsDisplay = true
            foreground.needsDisplay = true
            needsDisplay = true
        }
    }
    var previewUnavailable = false {
        didSet { updateAccessibilityStatus() }
    }
    private func updateAccessibilityStatus() {
        let status = item.unavailableReason ?? (item.isMinimized ? "minimized" : item.isCurrentWindow ? "Current window".localized : nil)
        let hints = [status, previewUnavailable ? "Preview unavailable" : nil].compactMap { $0 }
        toolTip = ([item.title] + hints).joined(separator: " — ")
        setAccessibilityLabel(toolTip)
    }
    var layoutSlot = CGRect.zero {
        didSet { updatePreviewFrame() }
    }
    private func updatePreviewFrame() {
        frame = LayoutHelperPreviewLayout.cardFrame(for: artwork.preview?.size, in: layoutSlot, isMinimized: item.isMinimized)
    }
    var preview: NSImage? {
        get { artwork.preview }
        set {
            if newValue != nil { previewUnavailable = false }
            artwork.setPreview(newValue, animated: !isHidden && window?.isVisible == true
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            updatePreviewFrame()
            needsDisplay = true
        }
    }
    override var allowsVibrancy: Bool { false }
    override var isFlipped: Bool { true }

    init(item: LayoutHelperPanel.Item) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        title = item.title
        isEnabled = item.unavailableReason == nil
        updateAccessibilityStatus()
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        refreshMaterialStyle()
        layer?.shadowRadius = 12
        layer?.shadowOffset = .zero
        artwork.wantsLayer = true
        artwork.icon = item.icon
        artwork.isMinimized = item.isMinimized
        artwork.setAccessibilityElement(false)
        addSubview(artwork)
        foreground.card = self
        foreground.wantsLayer = true
        foreground.setAccessibilityElement(false)
        addSubview(foreground)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    fileprivate func refreshMaterialStyle() {
        layer?.shadowOpacity = 0.07
        focusRingType = .none
    }
    override func layout() {
        super.layout()
        layer?.shadowPath = LayoutHelperAppearance.cardPath(
            in: bounds.insetBy(dx: -1.5, dy: -1.5),
            radius: LayoutHelperAppearance.cardCornerRadius + 1.5)
        artwork.frame = NSRect(x: 0, y: LayoutHelperPreviewLayout.titleHeight,
                               width: bounds.width, height: max(1, bounds.height - LayoutHelperPreviewLayout.titleHeight))
        foreground.frame = bounds
    }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on || (isEnabled && (window as? LayoutHelperPanel)?.keyboardSelection == true && window?.firstResponder === self)
        NSGraphicsContext.saveGraphicsState()
        // Match the screenshot's outer clip. Selection only changes the stroke,
        // so the title and screenshot keep the same edge when focus moves.
        NSBezierPath(cgPath: LayoutHelperAppearance.cardPath(in: bounds)).addClip()
        // An opaque backing also flattens alpha in captured windows and fallback icons.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor(srgbRed: dark ? 0.12 : 1, green: dark ? 0.12 : 1, blue: dark ? 0.12 : 1, alpha: 1).setFill()
        bounds.fill()
        let hasPreview = artwork.preview != nil
        if hasPreview {
            item.icon?.draw(in: NSRect(x: 16, y: 11, width: 18, height: 18), from: .zero,
                            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleX: CGFloat = hasPreview ? 44 : 16
        (item.title as NSString).draw(in: NSRect(x: titleX, y: 11, width: max(1, bounds.width - titleX - 16), height: 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        NSGraphicsContext.restoreGraphicsState()
        foreground.needsDisplay = true
    }

    fileprivate func drawForeground() {
        let selected = state == .on || (isEnabled && (window as? LayoutHelperPanel)?.keyboardSelection == true && window?.firstResponder === self)
        let lineWidth: CGFloat = selected ? 2 : 1
        let outline = NSBezierPath(cgPath: LayoutHelperAppearance.cardPath(
            in: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            radius: LayoutHelperAppearance.cardCornerRadius - lineWidth / 2))
        let imageArea = NSRect(x: 0, y: LayoutHelperPreviewLayout.titleHeight,
                               width: bounds.width, height: max(1, bounds.height - LayoutHelperPreviewLayout.titleHeight))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        if item.isMinimized {
            if artwork.preview != nil {
                NSColor.gray.withAlphaComponent(0.08).setFill()
                imageArea.fill()
            }
            let status = "Minimized" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = status.size(withAttributes: attributes)
            let badge = NSRect(x: imageArea.midX - (size.width + 20) / 2,
                               y: imageArea.maxY - 12 - 24, width: size.width + 20, height: 24)
            NSColor(calibratedWhite: 0.16, alpha: 0.72).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
            status.draw(at: CGPoint(x: badge.midX - size.width / 2,
                                   y: badge.midY - size.height / 2), withAttributes: attributes)
        }
        if item.isCurrentWindow {
            let status = "Current window".localized as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            let width = min(status.size(withAttributes: attributes).width + 12, max(1, bounds.width - 16))
            let badge = NSRect(x: 8, y: imageArea.minY + 6, width: width, height: 20)
            NSColor.controlBackgroundColor.withAlphaComponent(0.94).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
            status.draw(in: badge.insetBy(dx: 6, dy: 3), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        // Selection is an interaction cue, not a decoration on the glass.
        (selected ? LayoutHelperAppearance.selection : LayoutHelperAppearance.outline).setStroke()
        outline.lineWidth = lineWidth
        outline.stroke()
    }
}


final class LayoutHelperPermissionButton: NSButton {
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        title = "Enable previews…"
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .labelColor
        focusRingType = .exterior
        setAccessibilityIdentifier("layoutHelperEnablePreviews")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isHighlighted ? NSColor.selectedControlColor : NSColor.controlBackgroundColor).withAlphaComponent(0.92).setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        super.draw(dirtyRect)
    }
}
