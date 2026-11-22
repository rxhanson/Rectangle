import AppKit
import XCTest
@testable import Rectangle

@MainActor
func withDividerMaterialSettings(_ body: () throws -> Void) rethrows {
    let defaults = UserDefaults.standard
    let saved = ["overlayMaterial", "footprintBlur", "blurAppearance"].map {
        ($0, defaults.object(forKey: $0))
    }
    let originalMaterial = Defaults.overlayMaterial.value
    let originalAppearance = Defaults.blurAppearance.value
    defer {
        Defaults.overlayMaterial.value = originalMaterial
        Defaults.blurAppearance.value = originalAppearance
        for (key, value) in saved { defaults.set(value, forKey: key) }
        Notification.Name.blurStyleChanged.post()
    }
    try body()
}

@MainActor
func dividerDrawing(of view: NSView) throws -> NSBitmapImageRep {
    let image = NSImage(size: view.bounds.size, flipped: view.isFlipped) { _ in
        view.draw(view.bounds)
        return true
    }
    return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
}

@MainActor
func expectedDividerMaterial(_ requested: OverlayMaterial) -> OverlayMaterial {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return .noBlur }
    if #available(macOS 26, *) { return requested }
    return requested == .liquidGlass ? .standard : requested
}

@MainActor
func assertDividerSurface(_ surface: BlurSurfaceView, mode: OverlayMaterial,
                          file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertFalse(surface.isHiddenOrHasHiddenAncestor, file: file, line: line)
    XCTAssertFalse(surface.content.isHiddenOrHasHiddenAncestor, file: file, line: line)
    let visible = surface.subviews.filter { !$0.isHidden && $0.alphaValue > 0 }
    let legacy = visible.compactMap { $0 as? NSVisualEffectView }
    if mode == .standard {
        let effect = try XCTUnwrap(legacy.first, file: file, line: line)
        XCTAssertEqual(legacy.count, 1, file: file, line: line)
        XCTAssertEqual(effect.state, .active, file: file, line: line)
        XCTAssertEqual(effect.frame, surface.bounds, file: file, line: line)
    } else {
        XCTAssertTrue(legacy.isEmpty, file: file, line: line)
    }
    if mode == .noBlur {
        let fill = try XCTUnwrap(visible.first { $0 !== surface.content }, file: file, line: line)
        XCTAssertEqual(fill.frame, surface.bounds, file: file, line: line)
        let color = try XCTUnwrap(fill.layer?.backgroundColor, file: file, line: line)
        XCTAssertGreaterThan(color.alpha, 0.9, file: file, line: line)
    }
    if #available(macOS 26, *) {
        let native = visible.compactMap { $0 as? NSGlassEffectView }
        if mode == .liquidGlass {
            let glass = try XCTUnwrap(native.first, file: file, line: line)
            XCTAssertEqual(native.count, 1, file: file, line: line)
            XCTAssertEqual(glass.frame, surface.bounds, file: file, line: line)
            XCTAssertTrue(glass.contentView === surface.content, file: file, line: line)
        } else {
            XCTAssertTrue(native.isEmpty, file: file, line: line)
        }
    }
}

@MainActor
final class WindowDividerGlassHandleTests: XCTestCase {
    func testHandleKeepsVisibleGripAndHitTargetWhileMaterialChangesOnBothAxes() throws {
        try withDividerMaterialSettings {
            let panel = WindowDividerPanel()
            defer { panel.close() }
            let handle = try XCTUnwrap(panel.contentView as? WindowDividerHandle)
            let material = try XCTUnwrap(handle.subviews.compactMap { $0 as? BlurSurfaceView }.first)
            let grip = try XCTUnwrap(material.content.subviews.first)
            for axis: WindowSplitAxis in [.horizontal, .vertical] {
                panel.show(at: CGPoint(x: 200, y: 200), axis: axis)
                panel.holdVisible()
                let frame = panel.frame
                for choice: OverlayMaterial in [.standard, .liquidGlass, .noBlur, .standard] {
                    Defaults.overlayMaterial.value = choice
                    Notification.Name.blurStyleChanged.post()
                    handle.layoutSubtreeIfNeeded()
                    try assertDividerSurface(material, mode: expectedDividerMaterial(choice))
                    XCTAssertEqual(material.frame, handle.bounds.insetBy(dx: 3, dy: 3))
                    XCTAssertEqual(grip.frame, material.content.bounds)
                    XCTAssertEqual(grip.frame.size, material.bounds.size)
                    XCTAssertTrue(grip.superview === material.content)
                    XCTAssertFalse(grip.isHiddenOrHasHiddenAncestor)
                    let bitmap = try dividerDrawing(of: grip)
                    let x = bitmap.pixelsWide / 2, y = bitmap.pixelsHigh / 2
                    let ink = axis == .horizontal ? (x, y + 9) : (x + 9, y)
                    let clear = axis == .horizontal ? (x + 3, y + 9) : (x + 9, y + 3)
                    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: ink.0, y: ink.1)).alphaComponent, 0.1)
                    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: clear.0, y: clear.1)).alphaComponent, 0.05)
                    XCTAssertEqual(panel.frame, frame)
                    XCTAssertTrue(panel.acceptsPointer)
                    for point in [CGPoint(x: handle.bounds.midX, y: handle.bounds.midY), CGPoint(x: 1, y: 1)] {
                        XCTAssertTrue(handle.hitTest(point) === handle)
                    }
                }
            }
        }
    }

    func testLiveAppearanceAndMaterialPreserveContentAndInput() throws {
        try withDividerMaterialSettings {
            let panel = WindowDividerPanel()
            defer { panel.close() }
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.show(at: CGPoint(x: 200, y: 200))
            panel.holdVisible()
            let handle = try XCTUnwrap(panel.contentView as? WindowDividerHandle)
            let material = try XCTUnwrap(handle.subviews.compactMap { $0 as? BlurSurfaceView }.first)
            let originalGrip = try XCTUnwrap(material.content.subviews.first)
            var begins = 0, drags = 0, ends = 0, resets = 0
            panel.onBegin = { _ in begins += 1; return true }
            panel.onDrag = { _ in drags += 1 }
            panel.onEnd = { ends += 1 }
            panel.onReset = { resets += 1 }
            let frame = panel.frame
            let point = CGPoint(x: handle.bounds.midX, y: handle.bounds.midY)
            func mouse(_ type: NSEvent.EventType, clicks: Int) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
            }
            for choice: OverlayMaterial in [.liquidGlass, .standard, .noBlur] {
                Defaults.overlayMaterial.value = choice
                Notification.Name.blurStyleChanged.post()
                handle.layoutSubtreeIfNeeded()
                let mode = expectedDividerMaterial(choice)
                try assertDividerSurface(material, mode: mode)
                for appearance: BlurAppearance in [.dark, .light, .system] {
                    Defaults.blurAppearance.value = appearance
                    Notification.Name.blurAppearanceChanged.post()
                    let expected: NSAppearance.Name = mode != .noBlur && appearance == .light ? .aqua : .darkAqua
                    XCTAssertEqual(originalGrip.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
                    XCTAssertTrue(originalGrip.superview === material.content)
                    XCTAssertEqual(panel.frame, frame)
                }
                handle.mouseDown(with: try mouse(.leftMouseDown, clicks: 1))
                handle.mouseDragged(with: try mouse(.leftMouseDragged, clicks: 1))
                handle.mouseUp(with: try mouse(.leftMouseUp, clicks: 1))
                handle.mouseDown(with: try mouse(.leftMouseDown, clicks: 2))
            }
            XCTAssertEqual(begins, 3)
            XCTAssertEqual(drags, 6)
            XCTAssertEqual(ends, 3)
            XCTAssertEqual(resets, 3)
        }
    }
}

@MainActor
final class WindowDividerGlassLineTests: XCTestCase {
    func testFullLengthLineRendersInEveryMaterialAndAxis() throws {
        try withDividerMaterialSettings {
            for choice: OverlayMaterial in [.noBlur, .standard, .liquidGlass] {
                Defaults.overlayMaterial.value = choice
                for axis: WindowSplitAxis in [.horizontal, .vertical] {
                    let decoration = WindowDividerDecoration(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
                    decoration.axis = axis
                    decoration.dividerX = axis == .horizontal ? 60 : 40
                    let bitmap = try dividerDrawing(of: decoration)
                    for position in [5, axis == .horizontal ? 74 : 114] {
                        let center = axis == .horizontal ? (60, position) : (position, 40)
                        let outside = axis == .horizontal ? (54, position) : (position, 34)
                        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: center.0, y: center.1)).alphaComponent, 0.7)
                        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: outside.0, y: outside.1)).alphaComponent, 0.01)
                    }
                }
            }
        }
    }
}
