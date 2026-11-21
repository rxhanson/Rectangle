/// FreeformRegionTests.swift

import Foundation
import XCTest
@testable import Rectangle

final class FreeformRegionTests: XCTestCase {
    private let workArea = CGRect(x: -1200, y: 960, width: 1200, height: 800)

    func testRestoresTheSelectedAreaOnTheSameDisplay() throws {
        let rect = CGRect(x: -900, y: 1160, width: 600, height: 400)
        let id = UUID()
        let region = try XCTUnwrap(FreeformRegion(rect: rect, in: workArea, displayID: id))

        XCTAssertEqual(region.displayID, id)
        XCTAssertEqual(region.rect(in: workArea), rect)
    }

    func testSurvivesSavingAndDisplayRearrangement() throws {
        let rect = CGRect(x: -900, y: 1160, width: 600, height: 400)
        let region = try XCTUnwrap(FreeformRegion(rect: rect, in: workArea, displayID: UUID()))

        let restored = try JSONDecoder().decode(FreeformRegion.self, from: JSONEncoder().encode(region))

        XCTAssertEqual(restored, region)
        XCTAssertEqual(restored.rect(in: CGRect(x: 1500, y: -400, width: 1200, height: 800)),
                       CGRect(x: 1800, y: -200, width: 600, height: 400))
    }

    func testKeepsItsProportionsOnADifferentlySizedWorkArea() throws {
        let rect = CGRect(x: -900, y: 1160, width: 600, height: 400)
        let region = try XCTUnwrap(FreeformRegion(rect: rect, in: workArea, displayID: UUID()))

        XCTAssertEqual(region.rect(in: CGRect(x: 30, y: 40, width: 800, height: 1200)),
                       CGRect(x: 230, y: 340, width: 400, height: 600))
    }

    func testScaledEdgesLandOnWholePoints() throws {
        let region = try XCTUnwrap(FreeformRegion(rect: CGRect(x: 0, y: 0, width: 333, height: 333),
                                                  in: CGRect(x: 0, y: 0, width: 1000, height: 1000), displayID: nil))

        XCTAssertEqual(region.rect(in: CGRect(x: 0, y: 25, width: 1512, height: 957)),
                       CGRect(x: 0, y: 25, width: 503, height: 319))
    }

    func testCoversTheWholeWorkArea() throws {
        let region = try XCTUnwrap(FreeformRegion(rect: workArea, in: workArea, displayID: nil))

        XCTAssertEqual(region.rect(in: CGRect(x: 0, y: 0, width: 1512, height: 944)), CGRect(x: 0, y: 0, width: 1512, height: 944))
    }

    func testRejectsInvalidGeometry() {
        XCTAssertNil(FreeformRegion(rect: .zero, in: workArea, displayID: nil))
        XCTAssertNil(FreeformRegion(rect: CGRect(x: -900, y: 1160, width: 0, height: 400), in: workArea, displayID: nil))
        XCTAssertNil(FreeformRegion(rect: workArea, in: .infinite, displayID: nil))
        XCTAssertNil(FreeformRegion(rect: workArea, in: .null, displayID: nil))
        XCTAssertNil(FreeformRegion(rect: workArea.offsetBy(dx: -1, dy: 0), in: workArea, displayID: nil))
    }

    func testIgnoresSavedAreasOutsideTheWorkArea() throws {
        let saved = Data(#"{"relativeRect":[[0.5,0.5],[1,1]]}"#.utf8)
        let region = try JSONDecoder().decode(FreeformRegion.self, from: saved)

        XCTAssertNil(region.displayID)
        XCTAssertNil(region.rect(in: workArea))
    }
}
