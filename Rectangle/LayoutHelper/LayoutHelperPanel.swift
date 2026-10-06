import Cocoa

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
    private var updatingPreviewLayout = false
    private var visibleIDs: [CGWindowID] = []
    var visiblePreviewIDs: [CGWindowID] {
        cards.filter { $0.superview?.visibleRect.intersects($0.frame) == true }.map { $0.item.id }
    }
    var previewRequestIDs: [CGWindowID] {
        let visible = Set(visiblePreviewIDs)
        let missing = cards.filter { $0.preview == nil }
        // Keep uncaptured cards ahead of refreshes. Offscreen cards already own
        // their image even when the bounded shared cache has evicted it.
        return missing.filter { visible.contains($0.item.id) }.map { $0.item.id }
            + missing.filter { !visible.contains($0.item.id) }.map { $0.item.id }
            + cards.filter { $0.preview != nil && visible.contains($0.item.id) }.map { $0.item.id }
    }
    private var cards: [LayoutHelperCard] = []
    private var reusableCards: [LayoutHelperCard] = []
    private var candidateIDs: [CGWindowID] = []
    private var footerControls: [NSView] = []
    private var scrollView: NSScrollView?
    private var showingPermission = false
    private var waitsForPreviews = false
    private var shownMessage: String?
    private var backdrops: [LayoutHelperSurface] = []
    var interactionSuspended = false
    private var reflowUntil: TimeInterval = 0
    var isTransitioning: Bool { interactionSuspended || ProcessInfo.processInfo.systemUptime < reflowUntil }
    private var retiringBackdrops: [LayoutHelperSurface] = []
    private var retiringCards: [LayoutHelperCard] = []
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
              remainingRegions: [CGRect] = [], keyboardTriggered: Bool = false, images: [CGWindowID: NSImage] = [:], waitForPreviews: Bool = false,
              continuing: Bool = false) {
        if hasActiveSession {
            if self.frame != frame {
                regionEntranceOffset = Self.regionSlideOffset(from: self.frame, to: frame)
            } else if !isVisible {
                regionEntranceOffset = .zero
            }
        } else {
            regionEntranceOffset = nil
        }
        reconcileBackdrops(for: [frame] + remainingRegions, continuing: continuing)
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
            }
            applyImages(images, rearranging: geometryChanged)
            updateKeyViews()
            if keyboardSelection, let focused = firstResponder as? LayoutHelperCard, !focused.isEnabled {
                makeFirstResponder(cards.first(where: { $0.isEnabled && !$0.isHidden }))
            }
            return
        }
        let reusing = isVisible && showingPermission == offerPermission && shownMessage == message
            && (self.frame == frame || continuing)
        let regionChanged = continuing && self.frame != frame
        let oldCards = reusing ? cards : []
        let existingIDs = Set(oldCards.map { $0.item.id })
        let focusedID = (firstResponder as? LayoutHelperCard)?.item.id
        let scrollPosition = scrollView?.contentView.bounds.origin ?? .zero
        let scrollAnchor = oldCards.first { !$0.isHidden && $0.frame.maxY > scrollPosition.y }
        let anchorOffset = scrollAnchor.map { $0.frame.minY - scrollPosition.y }
        let oldFrames = Dictionary(uniqueKeysWithValues: oldCards.compactMap { card -> (CGWindowID, CGRect)? in
            guard let parent = card.superview, !card.isHidden else { return nil }
            let displayed = card.layer?.presentation()?.frame ?? card.frame
            return (card.item.id, convertToScreen(parent.convert(displayed, to: nil)))
        })
        let departingFrames = retiringCards.compactMap { card -> (LayoutHelperCard, CGRect)? in
            guard let parent = card.superview else { return nil }
            return (card, convertToScreen(parent.convert(card.frame, to: nil)))
        }
        reusableCards = oldCards
        configure(in: frame, items: items, offerPermission: offerPermission, message: message,
                  keyboardTriggered: keyboardTriggered, images: images, waitForPreviews: waitForPreviews,
                  separateBackground: true)
        makeFirstResponder(keyboardSelection
            ? cards.first(where: { $0.item.id == focusedID && $0.isEnabled && !$0.isHidden }) ?? initialFirstResponder
            : contentView)
        if reusing, let scroll = scrollView {
            var origin = scrollPosition
            if let anchor = scrollAnchor, let offset = anchorOffset,
               let card = cards.first(where: { $0.item.id == anchor.item.id }) {
                origin.y = card.frame.minY - offset
            }
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(
                CGRect(origin: origin, size: scroll.contentView.bounds.size)).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if let document = scrollView?.documentView {
            for (card, previous) in departingFrames {
                document.addSubview(card)
                card.frame = document.convert(convertFromScreen(previous), from: nil)
            }
        }
        contentView?.layoutSubtreeIfNeeded()
        displayIfNeeded()
        animatePresentation(excluding: existingIDs)
        if reusing { animateReflow(from: oldFrames, removed: oldCards.filter { !candidateIDs.contains($0.item.id) }, regionChanged: regionChanged) }
        if !isVisible { makeKeyAndOrderFront(nil) }
    }

    private func animateReflow(from oldFrames: [CGWindowID: CGRect], removed: [LayoutHelperCard], regionChanged: Bool) {
        let duration: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        reflowUntil = ProcessInfo.processInfo.systemUptime + duration
        let viewport = scrollView.map { convertToScreen($0.convert($0.bounds, to: nil)) }
        for card in cards {
            guard let previous = oldFrames[card.item.id], let parent = card.superview,
                  let layer = card.layer, !card.isHidden else { continue }
            let current = convertToScreen(parent.convert(card.frame, to: nil))
            guard current.width > 0, current.height > 0 else { continue }
            let scaleX = previous.width / current.width, scaleY = previous.height / current.height
            var transform = CATransform3DMakeScale(scaleX, scaleY, 1)
            transform.m41 = previous.minX - current.minX + current.width * layer.anchorPoint.x * (scaleX - 1)
            transform.m42 = current.maxY - previous.maxY + current.height * layer.anchorPoint.y * (scaleY - 1)
            layer.removeAnimation(forKey: "layoutHelperReflow")
            if duration > 0 {
                // A card outside the new viewport cannot move from its old position
                // without being clipped. Fade it in while the background resizes.
                let relocates = regionChanged && viewport?.contains(previous) != true
                let animation = CABasicAnimation(keyPath: relocates ? "opacity" : "transform")
                animation.fromValue = relocates ? 0 : NSValue(caTransform3D: transform)
                animation.toValue = relocates ? 1 : NSValue(caTransform3D: CATransform3DIdentity)
                animation.duration = duration
                animation.timingFunction = PreviewLayerTransition.deceleration
                layer.add(animation, forKey: "layoutHelperReflow")
            }
        }
        for card in removed {
            guard duration > 0, let previous = oldFrames[card.item.id],
                  let document = scrollView?.documentView else { card.removeFromSuperview(); continue }
            card.isEnabled = false
            card.setAccessibilityElement(false)
            document.addSubview(card)
            card.frame = document.convert(convertFromScreen(previous), from: nil)
            retiringCards.append(card)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                card.animator().alphaValue = 0
            } completionHandler: { [weak self, weak card] in
                guard let card else { return }
                card.removeFromSuperview()
                self?.retiringCards.removeAll { $0 === card }
            }
        }
    }

    static func regionSlideOffset(from previous: CGRect, to next: CGRect) -> CGPoint {
        // Screen coordinates increase upwards; card layers are flipped.
        let dx = previous.midX - next.midX
        let dy = next.midY - previous.midY
        let distance = hypot(dx, dy)
        guard distance > 0 else { return .zero }
        return CGPoint(x: dx / distance * 8, y: dy / distance * 8)
    }

    private func reconcileBackdrops(for regions: [CGRect], continuing: Bool = false) {
        let duration: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        if continuing, backdrops.count == regions.count,
           zip(backdrops, regions).allSatisfy({ $0.frame.intersects($1) }) {
            for (backdrop, region) in zip(backdrops, regions) { backdrop.transitionFrame(to: region, duration: duration) }
            return
        }
        for backdrop in backdrops where !regions.contains(backdrop.destinationFrame ?? backdrop.frame) {
            backdrop.stopFrameTransition()
            if continuing, duration > 0 {
                backdrop.ignoresMouseEvents = true
                retiringBackdrops.append(backdrop)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    backdrop.animator().alphaValue = 0
                } completionHandler: { [weak self, weak backdrop] in
                    guard let backdrop else { return }
                    backdrop.orderOut(nil)
                    self?.retiringBackdrops.removeAll { $0 === backdrop }
                }
            } else { backdrop.orderOut(nil) }
        }
        backdrops = regions.map { region in
            let backdrop: LayoutHelperSurface
            if let existing = backdrops.first(where: { ($0.destinationFrame ?? $0.frame) == region }) {
                backdrop = existing
            } else {
                backdrop = LayoutHelperSurface()
                backdrop.onDismiss = { [weak self] in self?.onDismiss?() }
                backdrop.prepare(in: region)
                if continuing, duration > 0 {
                    backdrop.alphaValue = 0
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = duration
                        backdrop.animator().alphaValue = 1
                    }
                }
            }
            if !backdrop.isVisible {
                if isVisible { backdrop.order(.below, relativeTo: windowNumber) }
                else { backdrop.orderFront(nil) }
            }
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
            let card = reusableCards.first { $0.item.id == item.id && $0.item.previewKey == item.previewKey }
                ?? LayoutHelperCard(item: item)
            card.item = item
            card.state = .off
            card.layoutSlot = frame.offsetBy(dx: horizontal, dy: top)
            card.preview = images[item.id]
            card.isHidden = waitsForPreviews && card.preview == nil
            card.target = self
            card.action = #selector(selectCard(_:))
            document.addSubview(card)
            return card
        }
        reusableCards.removeAll()
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
                if !self.updatingPreviewLayout { self.finishPresentation() }
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
        applyImages([id: image])
    }

    func updateImages(_ images: [CGWindowID: NSImage]) {
        applyImages(images)
        WindowAnimationDiagnostics.event("helper-preview-delivery", fields: ["count": images.count])
    }

    private func applyImages(_ images: [CGWindowID: NSImage], rearranging: Bool = false) {
        guard !showingPermission else { return }
        var geometryChanged = rearranging
        var updated: [LayoutHelperCard] = []
        for card in cards {
            guard let image = images[card.item.id] else { continue }
            if card.preview !== image {
                let previous = LayoutHelperPreviewLayout.sourceSize(for: card.preview?.size, fallback: card.item.sourceSize)
                let next = LayoutHelperPreviewLayout.sourceSize(for: image.size, fallback: card.item.sourceSize)
                geometryChanged = geometryChanged || previous != next
                card.preview = image
            }
            updated.append(card)
        }
        // Commit the whole delivery before arranging or revealing any card.
        if geometryChanged { arrangeUpdatedPreviews() }
        reveal(updated)
    }

    func previewFailed(for id: CGWindowID) {
        guard let card = cards.first(where: { $0.item.id == id }) else { return }
        if card.preview == nil { card.previewUnavailable = true }
        reveal(card)
    }

    private func arrangeUpdatedPreviews() {
        guard let scroll = scrollView, let document = scroll.documentView else { return }
        // Programmatic bounds notifications must not end other cards' entrances.
        updatingPreviewLayout = true
        defer { updatingPreviewLayout = false }
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
        let ids = visiblePreviewIDs
        if ids != visibleIDs { visibleIDs = ids; onVisiblePreviewsChanged?() }
    }

    private func reveal(_ card: LayoutHelperCard) {
        reveal([card])
    }

    private func reveal(_ updated: [LayoutHelperCard]) {
        let entering = updated.filter { $0.isHidden }
        guard !entering.isEmpty else { return }
        // Artwork and visibility commit together; normal AppKit drawing prepares
        // only visible cards, without a forced layout/display for each capture.
        entering.forEach { $0.isHidden = false }
        let ids = Set(entering.map { $0.item.id })
        animatePresentation(excluding: Set(cards.filter { !ids.contains($0.item.id) }.map { $0.item.id }), preserveExisting: true)
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
            card.layer?.removeAnimation(forKey: "layoutHelperReflow")
        }
    }

    func dismiss() {
        interactionSuspended = false; reflowUntil = 0
        retiringCards.forEach { $0.removeFromSuperview() }; retiringCards.removeAll()
        (backdrops + retiringBackdrops).forEach { $0.stopFrameTransition(); $0.orderOut(nil) }
        retiringBackdrops.removeAll(); reusableCards.removeAll()
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
        if isTransitioning,
           [.leftMouseDown, .leftMouseUp, .rightMouseDown].contains(event.type)
            || (isTransitioning && event.type == .keyDown && [36, 76, 49].contains(event.keyCode)) { return }
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
