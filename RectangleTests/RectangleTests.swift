//
//  RectangleTests.swift
//  RectangleTests
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import XCTest
@testable import Rectangle

class RectangleTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAsRectParams_usesCombinedDisplayFrame_whenSet() {
        let screen = NSScreen.main!
        let usableScreens = UsableScreens(currentScreen: screen, numScreens: 2)
        let combinedFrame = CGRect(x: 0, y: 0, width: 5120, height: 1600)
        let window = Window(id: 0, rect: CGRect(x: 100, y: 100, width: 400, height: 300))

        let params = WindowCalculationParameters(
            window: window,
            usableScreens: usableScreens,
            action: .center,
            lastAction: nil,
            ignoreTodo: false,
            combinedDisplayFrame: combinedFrame
        )

        let rectParams = params.asRectParams()

        XCTAssertEqual(rectParams.visibleFrameOfScreen, combinedFrame)
    }

    func testAsRectParams_ignoresCombinedDisplayFrame_whenExplicitVisibleFramePassed() {
        let screen = NSScreen.main!
        let usableScreens = UsableScreens(currentScreen: screen, numScreens: 2)
        let combinedFrame = CGRect(x: 0, y: 0, width: 5120, height: 1600)
        let explicitFrame = CGRect(x: 2560, y: 0, width: 2560, height: 1600)
        let window = Window(id: 0, rect: CGRect(x: 100, y: 100, width: 400, height: 300))

        let params = WindowCalculationParameters(
            window: window,
            usableScreens: usableScreens,
            action: .nextDisplay,
            lastAction: nil,
            ignoreTodo: false,
            combinedDisplayFrame: combinedFrame
        )

        let rectParams = params.asRectParams(visibleFrame: explicitFrame)

        XCTAssertEqual(rectParams.visibleFrameOfScreen, explicitFrame)
    }

    func testWithDifferentAction_preservesCombinedDisplayFrame() {
        let screen = NSScreen.main!
        let usableScreens = UsableScreens(currentScreen: screen, numScreens: 2)
        let combinedFrame = CGRect(x: 0, y: 0, width: 5120, height: 1600)
        let window = Window(id: 0, rect: CGRect(x: 100, y: 100, width: 400, height: 300))

        let params = WindowCalculationParameters(
            window: window,
            usableScreens: usableScreens,
            action: .leftHalf,
            lastAction: nil,
            ignoreTodo: false,
            combinedDisplayFrame: combinedFrame
        )

        let newParams = params.withDifferentAction(.rightHalf)

        XCTAssertEqual(newParams.combinedDisplayFrame, combinedFrame)
    }

}
