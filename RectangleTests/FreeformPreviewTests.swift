/// FreeformPreviewTests.swift

import AppKit
import XCTest
@testable import Rectangle

/// The icon that shows a Freeform preset's area in Settings.
@MainActor
final class FreeformPreviewTests: XCTestCase {
    private let workArea = CGRect(x: 0, y: 25, width: 1400, height: 875)

    private func region(_ rect: CGRect) throws -> FreeformRegion {
        try XCTUnwrap(FreeformRegion(rect: rect, in: workArea, displayID: nil))
    }

    func testMatchesTheSizeOfTheOtherWindowPositionIcons() throws {
        let leftHalf = NSImage(imageLiteralResourceName: "leftHalfTemplate")
        XCTAssertEqual(FreeformPreview.size, leftHalf.size)
        let image = FreeformPreview.image(for: try region(CGRect(x: 0, y: 25, width: 700, height: 875)))
        XCTAssertEqual(image.size, leftHalf.size)
        XCTAssertTrue(image.isTemplate)
    }

    func testALeftHalfLooksLikeTheLeftHalfIcon() throws {
        let preview = try IconPixels(FreeformPreview.image(for: try region(CGRect(x: 0, y: 25, width: 700, height: 875))))
        let leftHalf = try IconPixels(NSImage(imageLiteralResourceName: "leftHalfTemplate"))
        XCTAssertEqual(preview, leftHalf)
    }

    func testACenteredAreaLooksLikeTheCenterIcon() throws {
        // The Center icon's window is 16 × 8 points of the 28 × 18 point display.
        let area = CGRect(x: 1400 * 6 / 28, y: 25 + 875 * 5 / 18, width: 1400 * 16 / 28, height: 875 * 8 / 18)
        let preview = try IconPixels(FreeformPreview.image(for: try region(area)))
        let center = try IconPixels(NSImage(imageLiteralResourceName: "centerTemplate"))
        XCTAssertEqual(preview, center)
    }

    func testDrawsTheOutlineTheShadedDisplayAndTheWindow() throws {
        // The top right quarter.
        let pixels = try IconPixels(FreeformPreview.image(for: try region(CGRect(x: 700, y: 462.5, width: 700, height: 437.5))))

        XCTAssertTrue(pixels.alpha[0].allSatisfy { $0 == 1 })
        XCTAssertTrue(pixels.alpha[19].allSatisfy { $0 == 1 })
        XCTAssertTrue(pixels.alpha.allSatisfy { $0[0] == 1 && $0[29] == 1 })
        XCTAssertEqual(pixels.alpha[5][5], 0.4)
        XCTAssertEqual(pixels.opaqueRect(inside: FreeformPreview.screen), CGRect(x: 15, y: 10, width: 14, height: 9))
    }

    func testPlacesTheWindowWhereTheAreaIsOnTheDisplay() throws {
        let cases: [(area: CGRect, expected: CGRect)] = [
            (CGRect(x: 0, y: 25, width: 1400, height: 875), CGRect(x: 1, y: 1, width: 28, height: 18)),
            (CGRect(x: 0, y: 25, width: 700, height: 875), CGRect(x: 1, y: 1, width: 14, height: 18)),
            (CGRect(x: 0, y: 25, width: 1400, height: 437.5), CGRect(x: 1, y: 1, width: 28, height: 9)),
            (CGRect(x: 350, y: 243.75, width: 700, height: 437.5), CGRect(x: 8, y: 6, width: 14, height: 9)),
        ]
        for (area, expected) in cases {
            XCTAssertEqual(FreeformPreview.windowRect(for: try region(area)), expected, "\(area)")
        }
    }

    func testASmallAreaStillShowsAPoint() throws {
        let bottomLeft = FreeformPreview.windowRect(for: try region(CGRect(x: 0, y: 25, width: 10, height: 10)))
        XCTAssertEqual(bottomLeft, CGRect(x: 1, y: 1, width: 1, height: 1))
        let topRight = FreeformPreview.windowRect(for: try region(CGRect(x: 1390, y: 890, width: 10, height: 10)))
        XCTAssertEqual(topRight, CGRect(x: 28, y: 18, width: 1, height: 1))
        XCTAssertTrue(FreeformPreview.screen.contains(topRight))
    }

    func testAPresetHasAnIconOnlyOnceItsAreaIsSelected() throws {
        for action in FreeformCalculationTests.presets {
            let setting = try XCTUnwrap(action.freeformRegion)
            let saved = setting.typedValue
            defer { setting.typedValue = saved }

            setting.typedValue = nil
            XCTAssertEqual(action.image.size, .zero, action.name)

            let area = try region(CGRect(x: 0, y: 25, width: 700, height: 875))
            setting.typedValue = area
            XCTAssertEqual(try IconPixels(action.image), try IconPixels(FreeformPreview.image(for: area)), action.name)
        }
    }
}
