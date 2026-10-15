import XCTest
@testable import ScheduleCore

final class WatchPresentationTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value + "+08:00")! }
    var course: CourseOccurrence { CourseOccurrence(title: "高等数学", start: date("2026-10-15T08:00:00"), end: date("2026-10-15T09:40:00")) }
    func testProgressClampedAtBothEdges() {
        XCTAssertEqual(WatchPresentation.progress(for: course, at: date("2026-10-15T07:00:00")), 0)
        XCTAssertEqual(WatchPresentation.progress(for: course, at: date("2026-10-15T08:50:00")), 0.5)
        XCTAssertEqual(WatchPresentation.progress(for: course, at: date("2026-10-15T11:00:00")), 1)
        var invalid = course; invalid.end = invalid.start
        XCTAssertEqual(WatchPresentation.progress(for: invalid, at: invalid.start), 0)
    }
    func testRemainingTimeRoundsUpAndHandlesEnd() {
        XCTAssertEqual(WatchPresentation.remainingText(for: course, at: date("2026-10-15T09:05:00")), "还有35分钟下课")
        XCTAssertEqual(WatchPresentation.remainingText(for: course, at: date("2026-10-15T09:39:59")), "还有1分钟下课")
        XCTAssertEqual(WatchPresentation.remainingText(for: course, at: course.end), "即将下课")
    }
    func testUpcomingSameDayAndHourFormatting() {
        XCTAssertEqual(WatchPresentation.upcomingText(for: course, at: date("2026-10-15T07:45:00")), "15分钟后上课")
        XCTAssertEqual(WatchPresentation.upcomingText(for: course, at: date("2026-10-15T06:00:00")), "2小时后上课")
        XCTAssertEqual(WatchPresentation.upcomingText(for: course, at: date("2026-10-15T06:25:00")), "1小时35分钟后上课")
        XCTAssertEqual(WatchPresentation.upcomingText(for: course, at: course.start), "即将上课")
    }
    func testTomorrowUsesExplicitDateInsteadOfAmbiguousMinutes() {
        XCTAssertEqual(WatchPresentation.upcomingText(for: course, at: date("2026-10-14T20:00:00")), "10月15日 08:00 上课")
    }
    func testCoursePaletteDeterministicAndIndependentOfOccurrence() {
        let titles = ["高等数学", "大学英语", "程序设计", "大学物理", ""]
        for title in titles {
            let value = WatchPresentation.paletteIndex(for: title)
            XCTAssertTrue((0..<4).contains(value)); XCTAssertEqual(value, WatchPresentation.paletteIndex(for: title))
        }
        XCTAssertGreaterThan(Set(titles.map { WatchPresentation.paletteIndex(for: $0) }).count, 1)
    }
}
