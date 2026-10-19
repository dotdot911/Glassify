//
//  ReadmeMediaTests.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import XCTest

// Touches recorded for the README clips, one page per test.
final class ReadmeMediaTests: XCTestCase {
    private var app: XCUIApplication!
    private var origin: XCUICoordinate!

    private func open(page: Int) {
        app = XCUIApplication()
        app.launchArguments = ["-page", "\(page)"]
        app.launch()
        origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        sleep(2)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        origin.withOffset(CGVector(dx: x, dy: y))
    }

    func testGlass() {
        open(page: 0)
        point(380, 420).press(forDuration: 0.1, thenDragTo: point(380, 300), withVelocity: XCUIGestureVelocity(120),
                              thenHoldForDuration: 0.3)
        sleep(1)
        point(201, 434).press(forDuration: 0.6, thenDragTo: point(150, 480), withVelocity: XCUIGestureVelocity(100),
                              thenHoldForDuration: 0.6)
        sleep(1)
        point(380, 300).press(forDuration: 0.1, thenDragTo: point(380, 420), withVelocity: XCUIGestureVelocity(120),
                              thenHoldForDuration: 0.3)
        sleep(2)
    }

    func testContainer() {
        open(page: 0)
        point(201, 328).tap()
        sleep(2)
        point(201, 328).tap()
        sleep(2)
    }

    func testButtons() {
        open(page: 1)
        point(285, 215).press(forDuration: 0.8)
        sleep(1)
        point(188, 307).press(forDuration: 0.8)
        sleep(1)
        point(285, 400).press(forDuration: 0.8)
        sleep(1)
        point(188, 492).press(forDuration: 0.8)
        sleep(2)
    }

    func testControls() {
        open(page: 2)
        point(114, 205).tap()
        sleep(1)
        point(173, 280).press(forDuration: 0.2, thenDragTo: point(330, 280), withVelocity: XCUIGestureVelocity(250),
                              thenHoldForDuration: 0.4)
        sleep(1)
        point(227, 495).tap()
        sleep(1)
        point(114, 205).tap()
        sleep(2)
    }

    func testBars() {
        open(page: 3)
        point(201, 700).press(forDuration: 0.1, thenDragTo: point(201, 300), withVelocity: XCUIGestureVelocity(500),
                              thenHoldForDuration: 0.1)
        sleep(2)
        point(350, 84).press(forDuration: 0.6)
        sleep(2)
        point(201, 300).press(forDuration: 0.1, thenDragTo: point(201, 800), withVelocity: XCUIGestureVelocity(600),
                              thenHoldForDuration: 0.1)
        sleep(2)
    }
}
