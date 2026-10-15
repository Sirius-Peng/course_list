import XCTest

final class CourseListUITests: XCTestCase {
    func testICSSubscriptionPreviewPersistenceRefreshAndStop() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES", "-UITestICSFeed"]; app.launch()
        app.buttons["schedule.import"].tap(); app.buttons["链接订阅"].tap()
        let url = app.textFields["subscription.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap(); url.typeText("webcal://fixture.invalid/calendar.ics?token=fixture")
        app.buttons["subscription.preview"].tap()
        XCTAssertTrue(app.staticTexts["已下载，请核对课程和学期后确认订阅"].waitForExistence(timeout: 8))
        let confirm = app.buttons["schedule.confirmImport"]
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["Subscribed Lab"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-UITestICSFeed"]; app.launch()
        XCTAssertTrue(app.staticTexts["Subscribed Lab"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        let refresh = app.buttons["subscription.refresh"]
        for _ in 0..<12 where !refresh.isHittable { app.swipeUp() }
        XCTAssertTrue(refresh.waitForExistence(timeout: 5)); refresh.tap()
        XCTAssertTrue(app.staticTexts["已检查，订阅内容未变化"].waitForExistence(timeout: 8))
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "ICS subscription management"; proof.lifetime = .keepAlways; add(proof)
        app.buttons["subscription.stop"].tap(); app.sheets.buttons["停止订阅"].tap()
        XCTAssertTrue(app.staticTexts["已停止订阅，当前课程已保留"].waitForExistence(timeout: 5))
        app.tabBars.buttons["今日"].tap()
        XCTAssertTrue(app.staticTexts["Subscribed Lab"].firstMatch.waitForExistence(timeout: 5))
    }
    func testICSLinkFailureAndPreviewCancellationPreserveExistingSchedule() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES", "-UITestICSFeed"]; app.launch()
        app.buttons["schedule.demo"].tap(); app.buttons["导入"].tap(); app.buttons["链接订阅"].tap()
        let url = app.textFields["subscription.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        let invalid = "http://fixture.invalid/feed.ics"
        url.tap(); url.typeText(invalid); app.buttons["subscription.preview"].tap()
        let error = app.staticTexts["import.error"]
        for _ in 0..<4 where !error.exists { app.swipeUp() }
        XCTAssertTrue(error.waitForExistence(timeout: 5)); XCTAssertTrue(error.label.contains("HTTPS"))
        app.navigationBars.buttons["取消"].tap()
        app.buttons["导入"].tap(); app.buttons["链接订阅"].tap()
        url.tap(); url.typeText("https://fixture.invalid/not-calendar")
        app.buttons["subscription.preview"].tap()
        for _ in 0..<4 where !error.exists { app.swipeUp() }
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("ICS"))
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["演示"].waitForExistence(timeout: 5))
        app.buttons["导入"].tap(); app.buttons["链接订阅"].tap()
        url.tap(); url.typeText("https://fixture.invalid/calendar.ics")
        app.buttons["subscription.preview"].tap()
        XCTAssertTrue(app.staticTexts["已下载，请核对课程和学期后确认订阅"].waitForExistence(timeout: 8))
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["演示"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Subscribed Lab"].exists)
    }

    func testManualCourseSavePersistenceAndDelete() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES"]; app.launch()
        app.tabBars.buttons["课表"].tap()
        app.buttons["week.manualAdd"].tap()
        let title = app.textFields["manual.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manual.save"].isEnabled)
        title.tap(); title.typeText("Manual Lab")
        app.textFields["manual.location"].tap(); app.textFields["manual.location"].typeText("A201")
        app.buttons["manual.save"].tap()
        app.tabBars.buttons["今日"].tap()
        XCTAssertTrue(app.staticTexts["Manual Lab"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["Manual Lab"].waitForExistence(timeout: 5))
        app.staticTexts["Manual Lab"].tap()
        XCTAssertTrue(app.staticTexts["A201"].waitForExistence(timeout: 5))
        app.buttons["manual.delete"].tap()
        app.sheets.buttons["删除本次课程"].tap()
        XCTAssertTrue(app.staticTexts["今天没有课程"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Manual Lab"].exists)
    }
    func testManualWeeklyCourseAndCancel() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES"]; app.launch()
        app.buttons["schedule.manualAdd"].tap()
        app.textFields["manual.title"].tap(); app.textFields["manual.title"].typeText("Cancelled Class")
        app.navigationBars.buttons["取消"].tap()
        XCTAssertFalse(app.staticTexts["Cancelled Class"].exists)
        app.buttons["schedule.manualAdd"].tap()
        app.textFields["manual.title"].tap(); app.textFields["manual.title"].typeText("Weekly Seminar")
        let toggle = app.switches["manual.weekly"]
        // Dismiss the keyboard without changing the form.
        if app.buttons["完成输入"].exists { app.buttons["完成输入"].tap() }
        if !toggle.isHittable { app.swipeUp() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["manual.until"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Manual weekly course form"; proof.lifetime = .keepAlways; add(proof)
        app.buttons["manual.save"].tap()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["课程次数, 13"].waitForExistence(timeout: 5))
        app.tabBars.buttons["今日"].tap()
        XCTAssertTrue(app.staticTexts["Weekly Seminar"].waitForExistence(timeout: 5))
    }

    func testReminderSettingsAndForegroundBanner() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES"]; app.launch()
        app.tabBars.buttons["设置"].tap()
        let toggle = app.switches["reminder.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["允许"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        else if springboard.buttons["Allow"].exists { springboard.buttons["Allow"].tap() }
        else if app.alerts.buttons["Allow"].exists { app.alerts.buttons["Allow"].tap() }
        else if app.alerts.buttons["允许"].exists { app.alerts.buttons["允许"].tap() }
        let test = app.buttons["reminder.test"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: test)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        test.tap()
        XCTAssertTrue(springboard.staticTexts["课前提醒测试"].waitForExistence(timeout: 15))
        let proof = XCTAttachment(screenshot: springboard.screenshot()); proof.name = "Foreground course reminder banner"; proof.lifetime = .keepAlways; add(proof)
    }

    func testSchoolLoginFormReadyForHumanInput() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES"]; app.launch()
        app.buttons["schedule.import"].tap()
        app.buttons["学校拉取"].tap()
        XCTAssertTrue(app.textFields["auth.server"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["auth.username"].exists)
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        XCTAssertTrue(app.buttons["auth.health"].exists)
        XCTAssertFalse(app.buttons["auth.login"].isEnabled)
    }
    func testDemoScheduleAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["schedule.demo"].waitForExistence(timeout: 10))
        app.buttons["schedule.demo"].tap()
        XCTAssertTrue(app.staticTexts["演示"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "演示课表")).firstMatch.exists)
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.buttons["回到本周"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        for _ in 0..<4 where !app.staticTexts["iOS 26 锁屏小组件"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["iOS 26 锁屏小组件"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["清空课表"].isHittable { app.swipeDown() }
        app.buttons["清空课表"].tap()
        app.sheets.buttons["清空课表"].tap()
        app.tabBars.buttons["今日"].tap()
        XCTAssertTrue(app.buttons["schedule.import"].waitForExistence(timeout: 5))
    }
    func testImportFormAndCancel() throws {
        let app = XCUIApplication(); app.launchArguments = ["-UITestReset", "YES"]; app.launch()
        app.buttons["schedule.import"].tap()
        XCTAssertTrue(app.buttons["选择 .ics 文件"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第一周周一"].exists)
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["schedule.import"].waitForExistence(timeout: 5))
    }
}
