import XCTest
final class StartupTests: XCTestCase {
    func testStandaloneNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let welcome = app.buttons["Get Started"]
        let settings = app.buttons["Settings"]
        let ready = NSPredicate(format: "hittable == true")
        let appeared = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: welcome)], timeout: 8) == .completed || settings.isHittable
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "standalone-startup-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "standalone-startup"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(appeared, "Standalone phone must show onboarding or full navigation without a Mac connection")
        if welcome.exists { welcome.tap() }
        let local = app.buttons["Keep on this device only"]
        if local.waitForExistence(timeout: 3) { local.tap() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); XCTAssertTrue(settings.isHittable); settings.tap()
        XCTAssertTrue(app.navigationBars["Capture Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        for name in ["Capture", "To do", "Studio"] {
            let tab = app.segmentedControls.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), name); XCTAssertTrue(tab.isHittable, name); tab.tap(); XCTAssertTrue(tab.isSelected, name)
        }
        app.segmentedControls.buttons["Capture"].tap()
        app.buttons["Type a note instead of recording"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let sentinel = "Standalone startup regression thought"
        editor.typeText(sentinel)
        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["Type a note"].waitForExistence(timeout: 1))
        app.terminate(); app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Full navigation must survive relaunch")
        XCTAssertTrue(settings.isHittable)
        app.segmentedControls.buttons["Capture"].tap()
        XCTAssertTrue(app.staticTexts[sentinel].firstMatch.waitForExistence(timeout: 5), "Local note must survive relaunch")
        let final = XCTAttachment(screenshot: app.screenshot()); final.name = "standalone-note-persisted"; final.lifetime = .keepAlways; add(final)
    }
    func testClosedDuo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for iteration in 1...3 {
            app.launch()
            XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Record"].isHittable)
            XCTAssertFalse(app.buttons["Settings"].isHittable)
            XCTAssertFalse(app.buttons["Get Started"].isHittable)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "native-closed-\(iteration)"; tree.lifetime = .keepAlways; add(tree)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "native-closed-\(iteration)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
    func testOpenDuo() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let welcome = app.buttons["Get Started"]
        if welcome.waitForExistence(timeout: 5), welcome.isHittable { welcome.tap() }
        let local = app.buttons["Keep on this device only"]
        if local.waitForExistence(timeout: 3) { local.tap() }
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        XCTAssertTrue(app.staticTexts["To do"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "Known Duo shows the combined workspace")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "native-open-workspace"; shot.lifetime = .keepAlways; add(shot)
    }

}
