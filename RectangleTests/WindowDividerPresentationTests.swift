import AppKit
import XCTest
@testable import Rectangle

@MainActor
final class WindowDividerPresentationTests: XCTestCase {
    func testStandardBackdropFitsPreviewAndClipsAtSmallSizes() throws {
        try withDividerMaterialSettings {
            Defaults.overlayMaterial.value = .standard
            let guide = WindowDividerGuide(frame: CGRect(x: 0, y: 0, width: 440, height: 320))
            guide.setFrozenImage(nil)
            let surface = guide.backdrop.material
            for size in [CGSize(width: 400, height: 240), CGSize(width: 6, height: 3),
                         .zero, CGSize(width: 1, height: 3), CGSize(width: 180, height: 300)] {
                let preview = CGRect(origin: CGPoint(x: 9, y: 12), size: size)
                guide.previewBounds = preview
                guide.layoutSubtreeIfNeeded()
                XCTAssertEqual(guide.backdrop.frame, preview)
                XCTAssertEqual(surface.frame, guide.backdrop.bounds)
                XCTAssertEqual(guide.decoration.frame, preview)
                guard expectedDividerMaterial(.standard) == .standard else { continue }
                let effect = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSVisualEffectView }.first)
                if size == .zero {
                    XCTAssertNil(effect.maskImage)
                } else {
                    let cap = min(FootprintStyle.cornerRadius, (min(size.width, size.height) - 1) / 2)
                    let mask = try XCTUnwrap(effect.maskImage)
                    XCTAssertEqual(mask.capInsets.left, cap)
                    XCTAssertEqual(mask.capInsets.bottom, cap)
                    XCTAssertEqual(mask.size, CGSize(width: cap * 2 + 1, height: cap * 2 + 1))
                }
            }
        }
    }

    func testBothAxesKeepGutterAndOutlinesAboveBackdrop() throws {
        let guide = WindowDividerGuide(frame: CGRect(x: 0, y: 0, width: 180, height: 170))
        let decoration = guide.decoration
        XCTAssertGreaterThan(try XCTUnwrap(guide.subviews.firstIndex(of: decoration)),
                             try XCTUnwrap(guide.subviews.firstIndex(of: guide.backdrop)))
        guide.dividerX = 56
        guide.gap = 12
        for axis: WindowSplitAxis in [.horizontal, .vertical] {
            guide.axis = axis
            let preview = CGRect(origin: CGPoint(x: 9, y: 12), size: axis.size(CGSize(width: 120, height: 80)))
            guide.previewBounds = preview
            guide.layoutSubtreeIfNeeded()
            XCTAssertEqual(guide.backdrop.frame, preview)
            XCTAssertEqual(decoration.frame, preview)
            XCTAssertEqual(decoration.dividerX, 56)
            let outlines = axis == .horizontal
                ? [CGRect(x: 6.25, y: 6.25, width: 37.5, height: 67.5),
                   CGRect(x: 69.25, y: 7.25, width: 43.5, height: 65.5)]
                : [CGRect(x: 6.25, y: 76.25, width: 67.5, height: 37.5),
                   CGRect(x: 7.25, y: 7.25, width: 65.5, height: 43.5)]
            XCTAssertEqual(decoration.outlines, outlines)
        }
    }

    func testGuideKeepsCaptureCropAndMaterialThroughLiveChangesAndRetirement() throws {
        try withDividerMaterialSettings {
            let notifications = NotificationCenter()
            let guide = WindowDividerGuide(frame: CGRect(x: 0, y: 0, width: 180, height: 120), notifications: notifications)
            let preview = CGRect(x: 66, y: 15, width: 80, height: 80)
            guide.previewBounds = preview
            Defaults.overlayMaterial.value = .standard
            notifications.post(name: .blurStyleChanged, object: nil)
            guide.setFrozenImage(nil)
            guide.layoutSubtreeIfNeeded()
            let backdrop = guide.backdrop, captured = backdrop.capturedPreview
            for selection: OverlayMaterial in [.standard, .liquidGlass, .noBlur] {
                Defaults.overlayMaterial.value = selection
                notifications.post(name: .blurStyleChanged, object: nil)
                guide.layoutSubtreeIfNeeded()
                try assertDividerSurface(backdrop.material, mode: expectedDividerMaterial(selection))
                XCTAssertTrue(captured.isHidden)
                XCTAssertNil(guide.frozenImage)
                XCTAssertNil(captured.image)
                XCTAssertEqual(backdrop.material.blendingMode, .behindWindow)
            }
            let scene = NSImage(size: guide.bounds.size, flipped: false) { rect in
                NSColor.red.setFill(); rect.fill()
                NSColor.blue.setFill()
                CGRect(x: rect.midX, y: 0, width: rect.width / 2, height: rect.height).fill()
                return true
            }
            guide.setFrozenImage(try XCTUnwrap(scene.cgImage(forProposedRect: nil, context: nil, hints: nil)))
            let frozen = try XCTUnwrap(guide.frozenImage)
            let base = try dividerDrawing(of: guide)
            func pixel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
                try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            }
            for (x, channel) in [(5, \NSColor.redComponent), (175, \NSColor.blueComponent)] {
                let outside = try pixel(base, x, 60)
                XCTAssertEqual(outside.alphaComponent, 1, accuracy: 0.01)
                XCTAssertGreaterThan(outside[keyPath: channel], 0.95)
            }
            for selection: OverlayMaterial in [.liquidGlass, .standard, .noBlur, .liquidGlass] {
                Defaults.overlayMaterial.value = selection
                notifications.post(name: .configImported, object: nil)
                guide.layoutSubtreeIfNeeded()
                let mode = expectedDividerMaterial(selection)
                try assertDividerSurface(backdrop.material, mode: mode)
                XCTAssertTrue(guide.frozenImage === frozen)
                XCTAssertFalse(guide.decoration.isHidden)
                XCTAssertEqual(backdrop.frame, preview)
                XCTAssertTrue(captured.isDescendant(of: backdrop.material.content))
                XCTAssertEqual(captured.isHidden, mode == .standard)
                if mode == .standard {
                    let effect = try XCTUnwrap(backdrop.material.subviews.compactMap { $0 as? NSVisualEffectView }.first)
                    XCTAssertEqual(effect.blendingMode, .withinWindow)
                    continue
                }
                XCTAssertTrue(captured.image === frozen)
                XCTAssertEqual(captured.sourceFrame, preview)
                XCTAssertEqual(captured.frame, backdrop.bounds)
                let bitmap = try dividerDrawing(of: captured)
                // The edge lies at x=24 in this crop. Stretching the full capture into the preview puts it at x=40.
                let red = try pixel(bitmap, 8, 40), blue = try pixel(bitmap, 35, 40)
                XCTAssertEqual(red.alphaComponent, 1, accuracy: 0.02)
                XCTAssertEqual(blue.alphaComponent, 1, accuracy: 0.02)
                XCTAssertGreaterThan(red.redComponent, red.blueComponent + 0.1)
                XCTAssertGreaterThan(blue.blueComponent, blue.redComponent + 0.1)
                XCTAssertLessThan(try pixel(bitmap, 1, 40).alphaComponent, 0.05)
                XCTAssertLessThan(try pixel(bitmap, 2, 2).alphaComponent, 0.05)
            }
            guide.setFrozenImage(nil)
            guide.layoutSubtreeIfNeeded()
            XCTAssertNil(guide.frozenImage)
            XCTAssertNil(captured.image)
            XCTAssertTrue(captured.isHidden)
            XCTAssertEqual(backdrop.material.blendingMode, .behindWindow)
            guide.retire()
            Defaults.overlayMaterial.value = .standard
            notifications.post(name: .configImported, object: nil)
            XCTAssertTrue(backdrop.isHidden)
            XCTAssertTrue(guide.decoration.isHidden)
        }
    }

    func testFrozenGlassSmoothsTheCapturedEdgeAndReusesOnlyItsOwnCapture() throws {
        guard expectedDividerMaterial(.liquidGlass) == .liquidGlass else {
            throw XCTSkip("Requires native Glass with Reduce Transparency off")
        }
        try withDividerMaterialSettings {
            let notifications = NotificationCenter()
            let guide = WindowDividerGuide(frame: CGRect(x: 0, y: 0, width: 256, height: 120), notifications: notifications)
            let preview = CGRect(x: 64, y: 20, width: 128, height: 72)
            guide.previewBounds = preview
            let captured = guide.backdrop.capturedPreview

            func select(_ mode: OverlayMaterial) {
                Defaults.overlayMaterial.value = mode
                notifications.post(name: .blurStyleChanged, object: nil)
                guide.layoutSubtreeIfNeeded()
            }
            func capture(left: NSColor, right: NSColor) throws {
                let image = NSImage(size: guide.bounds.size, flipped: false) { rect in
                    left.setFill()
                    rect.fill()
                    right.setFill()
                    CGRect(x: rect.midX, y: 0, width: rect.width / 2, height: rect.height).fill()
                    return true
                }
                guide.setFrozenImage(try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
                guide.layoutSubtreeIfNeeded()
            }
            @MainActor func checkEdge(smooth: Bool, redOnLeft: Bool = true, line: UInt = #line) throws {
                let bitmap = try dividerDrawing(of: captured)
                func signal(at x: Int) throws -> CGFloat {
                    let pixel = Int((CGFloat(x) + 0.5) * CGFloat(bitmap.pixelsWide) / preview.width)
                    let color = try XCTUnwrap(bitmap.colorAt(x: pixel, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
                    return color.redComponent - color.blueComponent
                }
                // Normalize each material to its own colors. A uniform tint can change contrast but cannot soften this edge.
                let left = try signal(at: 16), right = try signal(at: 112)
                let contrast = left - right
                XCTAssertGreaterThan(redOnLeft ? contrast : -contrast, 0.4, line: line)
                guard abs(contrast) > 0.01 else { return }
                let before = (try signal(at: smooth ? 63 : 62) - right) / contrast
                let after = (try signal(at: smooth ? 64 : 65) - right) / contrast
                if smooth {
                    XCTAssertLessThan(before, 0.95, line: line)
                    XCTAssertGreaterThan(after, 0.05, line: line)
                    XCTAssertGreaterThanOrEqual(before + 0.02, after, line: line)
                } else {
                    XCTAssertEqual(before, 1, accuracy: 0.04, line: line)
                    XCTAssertEqual(after, 0, accuracy: 0.04, line: line)
                }
            }

            select(.noBlur)
            try capture(left: .red, right: .blue)
            let original = try XCTUnwrap(guide.frozenImage)
            XCTAssertTrue(captured.image === original)
            XCTAssertNil(captured.frostedImage)
            try checkEdge(smooth: false)
            select(.liquidGlass)
            try checkEdge(smooth: true)
            let frosted = try XCTUnwrap(captured.frostedImage)
            XCTAssertFalse(frosted === original)
            select(.standard)
            XCTAssertTrue(captured.frostedImage === frosted)
            select(.noBlur)
            try checkEdge(smooth: false)
            select(.liquidGlass)
            Defaults.blurAppearance.value = .dark
            notifications.post(name: .blurAppearanceChanged, object: nil)
            guide.previewBounds = preview.offsetBy(dx: 0, dy: 5)
            guide.layoutSubtreeIfNeeded()
            try checkEdge(smooth: true)
            XCTAssertTrue(captured.image === original)
            XCTAssertTrue(captured.frostedImage === frosted)

            // A second acquisition with the same dimensions must not show the cached colors from the first.
            try capture(left: .blue, right: .red)
            try checkEdge(smooth: true, redOnLeft: false)
            let replacement = try XCTUnwrap(guide.frozenImage)
            let replacementFrost = try XCTUnwrap(captured.frostedImage)
            XCTAssertFalse(replacement === original)
            XCTAssertTrue(captured.image === replacement)
            XCTAssertFalse(replacementFrost === frosted)
            guide.setFrozenImage(nil)
            XCTAssertNil(captured.image)
            XCTAssertNil(captured.frostedImage)
        }
    }

    func testOverlayFollowsAppearanceThroughLiveChangesAndImport() throws {
        try withDividerMaterialSettings {
            Defaults.overlayMaterial.value = .standard
            Defaults.blurAppearance.value = .light
            let notifications = NotificationCenter()
            let guide = WindowDividerGuide(frame: .zero, notifications: notifications)
            let window = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = guide
            for (choice, notification) in [(BlurAppearance.dark, Notification.Name.blurAppearanceChanged),
                                           (.light, .configImported), (.system, .blurAppearanceChanged)] {
                Defaults.blurAppearance.value = choice
                notifications.post(name: notification, object: nil)
                let expected: NSAppearance.Name = expectedDividerMaterial(.standard) == .standard && choice == .light ? .aqua : .darkAqua
                for view in [guide, guide.backdrop, guide.decoration] as [NSView] {
                    XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
                }
            }
        }
    }

    func testDividerMonitoringWaitsForAccessibilitySetup() {
        let manager = WindowDividerManager()
        let defaults = UserDefaults.standard
        let preferences = [Defaults.windowDivider, Defaults.windowDividerEnhanced]
        let saved = preferences.map { ($0, $0.enabled, defaults.object(forKey: $0.key)) }
        defer {
            Defaults.windowDivider.enabled = false
            manager.refreshMonitoring()
            for (preference, enabled, stored) in saved {
                preference.enabled = enabled
                defaults.set(stored, forKey: preference.key)
            }
        }

        Defaults.windowDivider.enabled = true
        Defaults.windowDividerEnhanced.enabled = false
        manager.refreshMonitoring()
        XCTAssertFalse(manager.monitoring)

        manager.start()
        XCTAssertTrue(manager.monitoring)

        Defaults.windowDivider.enabled = false
        manager.refreshMonitoring()
        XCTAssertFalse(manager.monitoring)
    }

    func testReloadingDividerSettingsDoesNotWriteThemBack() {
        let defaults = UserDefaults.standard
        let preferences = [Defaults.windowDivider, Defaults.windowDividerEnhanced]
        let saved = preferences.map { ($0, $0.enabled, defaults.object(forKey: $0.key)) }
        defer {
            for (preference, enabled, stored) in saved {
                preference.enabled = enabled
                defaults.set(stored, forKey: preference.key)
            }
        }

        for preference in preferences { preference.enabled = false }
        let viewModel = BehaviorSettingsViewModel()
        // Simulate settings already updated in memory with no stored override.
        for preference in preferences {
            preference.enabled = true
            defaults.removeObject(forKey: preference.key)
        }

        viewModel.reloadFromDefaults()

        XCTAssertTrue(viewModel.windowDivider)
        XCTAssertTrue(viewModel.windowDividerEnhanced)
        for preference in preferences { XCTAssertNil(defaults.object(forKey: preference.key)) }
    }

    func testStandardTransitionNeverChecksScreenRecording() {
        let capture = WindowDividerSnapshot.shouldCapture(enhanced: false) {
            XCTFail("Standard dragging should not query Screen Recording permission")
            return false
        }
        XCTAssertFalse(capture)
        XCTAssertFalse(WindowDividerSnapshot.shouldCapture(enhanced: true) { false })
    }

    func testDecliningEnhancedCaptureKeepsSystemConsentUnrequested() async {
        let flow = WindowCapturePermissionFlow(isAllowed: { false }, explain: { false }, request: {
            XCTFail("Declining the explanation should not open the system consent prompt")
            return false
        }, openSettings: { XCTFail("Declining should not open System Settings") })

        let outcome = await flow.run()
        XCTAssertEqual(outcome, .declined)
    }

    func testBothHandleOrientationsAcceptDragAndEqualSplit() throws {
        let panel = WindowDividerPanel()
        defer { panel.close() }
        var began = 0
        var ended = 0
        var previews = 0
        var equalized = 0
        panel.onBegin = { _ in began += 1; return true }
        panel.onDrag = { _ in previews += 1 }
        panel.onEnd = { ended += 1 }
        panel.onReset = { equalized += 1 }
        let handle = try XCTUnwrap(panel.contentView as? WindowDividerHandle)
        for axis: WindowSplitAxis in [.horizontal, .vertical] {
            panel.show(at: CGPoint(x: 200, y: 200), axis: axis)
            panel.holdVisible()
            let middle = CGPoint(x: handle.bounds.midX, y: handle.bounds.midY)
            XCTAssertTrue(handle.hitTest(middle) === handle)
            func mouseEvent(_ type: NSEvent.EventType, clicks: Int) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: middle, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
            }
            handle.mouseDown(with: try mouseEvent(.leftMouseDown, clicks: 1))
            handle.mouseUp(with: try mouseEvent(.leftMouseUp, clicks: 1))
            handle.mouseDown(with: try mouseEvent(.leftMouseDown, clicks: 2))
        }
        XCTAssertEqual(began, 2)
        XCTAssertEqual(ended, 2)
        XCTAssertEqual(previews, 2, "The release position must survive a coalesced final drag event")
        XCTAssertEqual(equalized, 2)
    }
}

final class WindowDividerTrailingMinimumTests: XCTestCase {
    func testRightAndBottomMinimumProbesWaitForRoomInsideThePair() throws {
        for axis in [WindowSplitAxis.horizontal, .vertical] {
            let originals = [axis.rect(CGRect(x: -220, y: 40, width: 500, height: 600)),
                             axis.rect(CGRect(x: 290, y: 40, width: 500, height: 600))]
            let outer = originals[0].union(originals[1])
            var frames = originals
            var server = originals
            var time: TimeInterval = 0
            var serverMoveAt: TimeInterval?
            var grew = false
            let placement = try XCTUnwrap(WindowDividerPlacement(left: originals[0], right: originals[1], axis: axis,
                divider: 470, minimumLeft: 100, minimumRight: 100, write: { isLeft, target, attribute in
                    XCTAssertFalse(isLeft, "The other member cannot grow while the trailing member is at minimum")
                    guard outer.contains(target) else {
                        XCTFail("The probe requested a window outside the pair")
                        return false
                    }
                    let previous = axis.rect(frames[1])
                    var requested = axis.rect(target)
                    if attribute == .position {
                        frames[1].origin = target.origin
                        if requested.minX < previous.minX {
                            serverMoveAt = time + 0.15
                            return true
                        }
                    } else {
                        if requested.width > previous.width {
                            XCTAssertEqual(server[1], frames[1], "Wait for WindowServer to confirm the inward move")
                            grew = true
                        }
                        requested.size.width = max(500, requested.width)
                        frames[1].size = axis.rect(requested).size
                    }
                    server[1] = frames[1]
                    return true
                }, read: { frames[$0 ? 0 : 1] }, acknowledged: { server[$0 ? 0 : 1] == $1 }))
            let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: {
                time += 0.025
                if let deadline = serverMoveAt, time >= deadline {
                    server[1] = frames[1]
                    serverMoveAt = nil
                }
            }))
            XCTAssertTrue(grew)
            XCTAssertTrue(result.minimumSizeReached)
            XCTAssertFalse(result.rolledBack)
            XCTAssertEqual(result.left, originals[0])
            XCTAssertEqual(result.right, originals[1])
        }
    }

    func testEscapeWhilePreparingProbeRestoresWithoutGrowing() throws {
        let originals = [CGRect(x: 0, y: 0, width: 500, height: 400), CGRect(x: 500, y: 0, width: 500, height: 400)]
        var frames = originals
        var time: TimeInterval = 0
        var escape = false
        let placement = try XCTUnwrap(WindowDividerPlacement(left: originals[0], right: originals[1], axis: .horizontal,
            divider: 700, minimumLeft: 100, minimumRight: 100, write: { _, requested, attribute in
                if attribute == .position {
                    frames[1].origin = requested.origin
                    if requested.minX < originals[1].minX { escape = true }
                } else {
                    XCTAssertLessThanOrEqual(requested.width, originals[1].width, "Escape cancels the pending growth")
                }
                return true
            }, read: { frames[$0 ? 0 : 1] }, acknowledged: { frames[$0 ? 0 : 1] == $1 }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, shouldRollback: { escape },
            now: { time }, pause: { time += 0.025 }))
        XCTAssertTrue(escape)
        XCTAssertEqual(frames, originals)
        XCTAssertTrue(result.rolledBack)
        XCTAssertFalse(result.minimumSizeReached)
    }
}
