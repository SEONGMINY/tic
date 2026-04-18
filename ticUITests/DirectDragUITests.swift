import XCTest

final class DirectDragUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSameDayTimedBlockDragMovesVisibly() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TIC_DRAG_DEBUG"] = "1"
        app.launch()
        sleep(2)

        openTodayDayViewIfNeeded(in: app)

        let event = try XCTUnwrap(findMidnightEvent(in: app), "00:00 timed block not found")
        let eventId = event.identifier
        let beforeValue = stringValue(of: event)

        print("UI-DIRECT before event:", eventId, beforeValue)
        print("UI-DIRECT debug before:", debugOverlayLabel(in: app))

        event.press(forDuration: 0.8)
        sleep(1)

        let editableEvent = app.descendants(matching: .any).matching(identifier: eventId).firstMatch
        XCTAssertTrue(editableEvent.waitForExistence(timeout: 3), "Editable event block not found")

        print("UI-DIRECT debug edit:", debugOverlayLabel(in: app))

        let start = editableEvent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = editableEvent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 6.5))

        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(2)

        let movedEvent = app.descendants(matching: .any).matching(identifier: eventId).firstMatch
        XCTAssertTrue(movedEvent.waitForExistence(timeout: 3), "Moved event block not found")

        let afterValue = stringValue(of: movedEvent)
        print("UI-DIRECT after event:", eventId, afterValue)
        print("UI-DIRECT debug after:", debugOverlayLabel(in: app))

        XCTAssertNotEqual(afterValue, beforeValue, "Expected timed block time range to change after drag")
        XCTAssertFalse(afterValue.contains("00:00"), "Expected timed block to leave the 00:00 slot after drag")
    }

    private func openTodayDayViewIfNeeded(in app: XCUIApplication) {
        let todayLabel = String(Calendar.current.component(.day, from: Date()))
        let todayCell = app.staticTexts[todayLabel].firstMatch

        if todayCell.waitForExistence(timeout: 3) {
            todayCell.tap()
            sleep(2)
        }
    }

    private func findMidnightEvent(in app: XCUIApplication) -> XCUIElement? {
        if let event = firstMidnightEvent(in: app) {
            return event
        }

        let scrollView = app.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else {
            return nil
        }

        for _ in 0..<4 {
            scrollView.swipeDown()
            if let event = firstMidnightEvent(in: app) {
                return event
            }
        }

        return nil
    }

    private func firstMidnightEvent(in app: XCUIApplication) -> XCUIElement? {
        let query = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "timeline-event-")
        )

        for element in query.allElementsBoundByIndex {
            let value = stringValue(of: element)
            if value.contains("00:00") {
                return element
            }
        }

        return nil
    }

    private func stringValue(of element: XCUIElement) -> String {
        if let value = element.value as? String {
            return value
        }
        return "\(element.value ?? "nil")"
    }

    private func debugOverlayLabel(in app: XCUIApplication) -> String {
        let overlay = app.staticTexts["drag-debug-overlay"]
        guard overlay.waitForExistence(timeout: 2) else {
            return "debug-overlay-missing"
        }
        return overlay.label.replacingOccurrences(of: "\n", with: " | ")
    }
}
