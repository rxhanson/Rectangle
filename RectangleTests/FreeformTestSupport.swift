/// FreeformTestSupport.swift

import AppKit
import Carbon
import XCTest
@testable import Rectangle

/// Drives the Freeform selection overlay with real events, sent through its panels the way
/// AppKit delivers them, rather than by calling the view's handlers.
@MainActor
enum FreeformEvents {
    static func mouse(_ type: NSEvent.EventType, at screenPoint: CGPoint, in window: NSWindow,
                      modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screenPoint),
                                         modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }

    static func key(_ type: NSEvent.EventType, _ keyCode: Int, characters: String, in window: NSWindow,
                    isARepeat: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: isARepeat, keyCode: UInt16(keyCode)))
    }

    static func flags(_ modifiers: NSEvent.ModifierFlags, keyCode: Int, in window: NSWindow) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true))
        cgEvent.type = .flagsChanged
        cgEvent.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    static func escape(in window: NSWindow) throws -> NSEvent {
        try key(.keyDown, kVK_Escape, characters: "\u{1b}", in: window)
    }

    /// Presses at `from`, drags through `through`, and releases at `to`.
    static func drag(in panel: NSWindow, from: CGPoint, through: [CGPoint] = [], to: CGPoint,
                     modifiers: NSEvent.ModifierFlags = []) throws {
        panel.sendEvent(try mouse(.leftMouseDown, at: from, in: panel, modifiers: modifiers))
        for point in through {
            panel.sendEvent(try mouse(.leftMouseDragged, at: point, in: panel, modifiers: modifiers))
        }
        panel.sendEvent(try mouse(.leftMouseUp, at: to, in: panel, modifiers: modifiers))
    }
}

@MainActor
enum FreeformTestWindows {
    static func make(frame: CGRect = CGRect(x: 100, y: 100, width: 300, height: 240),
                     contentViewController: NSViewController? = nil) -> NSWindow {
        _ = NSApplication.shared
        let window: NSWindow
        if let contentViewController {
            window = NSWindow(contentViewController: contentViewController)
            window.setFrame(frame, display: false)
        } else {
            window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        }
        window.isReleasedWhenClosed = false
        return window
    }

    static var visibleOverlays: [FreeformSelectionPanel] {
        NSApp.windows.compactMap { $0 as? FreeformSelectionPanel }.filter(\.isVisible)
    }
}

/// Checks that a rect matches to within rounding error.
func assertFreeformRect(_ actual: CGRect?, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
    guard let actual else {
        XCTFail("Expected \(expected), got nil", file: file, line: line)
        return
    }
    let close = [actual.minX - expected.minX, actual.minY - expected.minY,
                 actual.width - expected.width, actual.height - expected.height].allSatisfy { abs($0) < 0.001 }
    XCTAssertTrue(close, "Expected \(expected), got \(actual)", file: file, line: line)
}

/// The opacity of each point of an icon, drawn at one pixel per point.
struct IconPixels: Equatable {
    let width: Int, height: Int
    /// Rows from the bottom, as in AppKit coordinates.
    let alpha: [[CGFloat]]

    init(_ image: NSImage) throws {
        width = Int(image.size.width)
        height = Int(image.size.height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let (width, height) = (width, height)
        alpha = (0..<height).map { y in
            (0..<width).map { x in
                let alpha = bitmap.colorAt(x: x, y: height - 1 - y)?.alphaComponent ?? 0
                return (alpha * 100).rounded() / 100
            }
        }
    }

    /// The points drawn fully opaque, as one rectangle, or nil if they aren't one.
    func opaqueRect(inside area: CGRect) -> CGRect? {
        var points: [(Int, Int)] = []
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) where alpha[y][x] == 1 {
                points.append((x, y))
            }
        }
        guard let minX = points.map(\.0).min(), let maxX = points.map(\.0).max(),
              let minY = points.map(\.1).min(), let maxY = points.map(\.1).max(),
              points.count == (maxX - minX + 1) * (maxY - minY + 1) else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
