//
//  ComparisonUITests.swift
//  Comparison
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import XCTest

// The same touches on both apps, for the side-by-side videos.
final class ComparisonUITests: XCTestCase {
    private var app: XCUIApplication!
    private var origin: XCUICoordinate!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
        origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        sleep(2)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        origin.withOffset(CGVector(dx: x, dy: y))
    }

    private func tab(_ index: CGFloat) -> XCUICoordinate {
        let frame = app.windows.firstMatch.frame
        let barWidth: CGFloat = 274
        let x = (frame.width - barWidth) / 2 + 51 + index * 86
        return point(x, frame.height - 21 - 31)
    }

    func testTour() {
        let frame = app.windows.firstMatch.frame
        let midX = frame.width / 2
        point(midX, frame.height * 0.7).press(forDuration: 0.1, thenDragTo: point(midX, frame.height * 0.25),
                                               withVelocity: XCUIGestureVelocity(350), thenHoldForDuration: 0.3)
        sleep(1)
        point(midX, frame.height * 0.7).press(forDuration: 0.1, thenDragTo: point(midX, frame.height * 0.25),
                                               withVelocity: XCUIGestureVelocity(350), thenHoldForDuration: 0.3)
        sleep(1)
        point(midX, frame.height * 0.25).press(forDuration: 0.1, thenDragTo: point(midX, frame.height * 0.75),
                                                withVelocity: XCUIGestureVelocity(500), thenHoldForDuration: 0.3)
        sleep(1)
        tab(0).press(forDuration: 0.5, thenDragTo: tab(2), withVelocity: XCUIGestureVelocity(200),
                     thenHoldForDuration: 0.6)
        sleep(1)
        tab(2).press(forDuration: 0.5, thenDragTo: tab(0), withVelocity: XCUIGestureVelocity(200),
                     thenHoldForDuration: 0.6)
        sleep(1)
        tab(1).tap()
        sleep(1)
        tab(2).tap()
        sleep(1)
        tab(0).tap()
        sleep(2)
    }

    func testReadmeTour() {
        let frame = app.windows.firstMatch.frame
        let midX = frame.width / 2
        point(midX, frame.height * 0.7).press(forDuration: 0.1, thenDragTo: point(midX, frame.height * 0.3),
                                               withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 0.2)
        sleep(1)
        tab(0).press(forDuration: 0.4, thenDragTo: tab(2), withVelocity: XCUIGestureVelocity(250),
                     thenHoldForDuration: 0.5)
        sleep(1)
        tab(2).press(forDuration: 0.4, thenDragTo: tab(1), withVelocity: XCUIGestureVelocity(250),
                     thenHoldForDuration: 0.4)
        sleep(1)
        point(midX, frame.height * 0.75).press(forDuration: 0.1, thenDragTo: point(midX, frame.height * 0.3),
                                                withVelocity: XCUIGestureVelocity(600), thenHoldForDuration: 0.1)
        sleep(2)
        app.buttons["Edit"].firstMatch.press(forDuration: 0.6)
        sleep(1)
        tab(2).tap()
        sleep(1)
        tab(0).tap()
        sleep(2)
    }

    func testTapTabs() {
        tab(2).tap()
        sleep(3)
    }

    func testSlowLensDrag() {
        tab(0).press(forDuration: 0.6, thenDragTo: tab(2), withVelocity: XCUIGestureVelocity(80), thenHoldForDuration: 1)
        sleep(2)
        tab(2).press(forDuration: 0.6, thenDragTo: tab(0), withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 1)
        sleep(2)
    }

    func testPressNavButtons() {
        tab(1).tap()
        sleep(2)
        let edit = app.buttons["Edit"].firstMatch
        edit.press(forDuration: 1.5)
        sleep(2)
        let frame = edit.frame
        let filter = point(app.windows.firstMatch.frame.width - frame.minX - frame.height / 2, frame.midY)
        filter.press(forDuration: 1.5)
        sleep(2)
        let center = edit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.6, thenDragTo: center.withOffset(CGVector(dx: 60, dy: 40)),
                     withVelocity: XCUIGestureVelocity(150), thenHoldForDuration: 0.8)
        sleep(2)
    }

    func testHoldOnMiddleTab() {
        tab(1).tap()
        sleep(20)
    }

    func testHoldOnLastTab() {
        tab(2).tap()
        sleep(20)
    }
}
