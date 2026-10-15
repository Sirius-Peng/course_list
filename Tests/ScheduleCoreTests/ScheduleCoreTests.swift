import XCTest
@testable import ScheduleCore

final class ScheduleCoreTests: XCTestCase {
    func date(_ value: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: value + "+08:00")!
    }
    func fixture() throws -> [CourseOccurrence] {
        let url = Bundle.module.url(forResource: "bit101", withExtension: "ics", subdirectory: "Fixtures")!
        return try ICSParser().parse(String(contentsOf: url, encoding: .utf8))
    }
    func snapshot() throws -> ScheduleSnapshot {
        ScheduleSnapshot(origin: "phone", revision: 1, fetchedAt: date("2026-10-12T00:00:00"),
            semester: Semester(name: "2026-2027-1", firstMonday: date("2026-09-07T00:00:00"), end: date("2027-01-18T00:00:00")), courses: try fixture())
    }
    func testBITFormatAndLocation() throws {
        let c = try fixture(); XCTAssertEqual(c.count, 2); XCTAssertEqual(c[0].displayLocation, "良乡理教楼 201")
        XCTAssertEqual(c[0].timeRange, "08:00–09:40")
    }
    func testExactClassBoundaries() throws {
        let s = try snapshot()
        for (time, expected) in [("07:59:00", CoursePhase.upcoming), ("08:00:00", .current), ("09:39:00", .current), ("09:40:00", .upcoming)] {
            XCTAssertEqual(ScheduleEngine.status(in: s, at: date("2026-10-13T" + time)).phase, expected)
        }
    }
    func testNextCourseAcrossDaysAndSemesterEnd() throws {
        let s = try snapshot(), state = ScheduleEngine.status(in: s, at: date("2026-10-13T10:00:00"))
        XCTAssertEqual(state.course?.title, "程序设计")
        XCTAssertEqual(ScheduleEngine.status(in: s, at: date("2026-10-15T08:00:00")).phase, .empty)
        XCTAssertEqual(ScheduleEngine.status(in: s, at: date("2027-01-18T00:00:00")).phase, .expired)
        XCTAssertEqual(ScheduleEngine.status(in: nil, at: Date()).phase, .needsImport)
    }
    func testUIDIndependentDeduplication() throws {
        let c = try fixture(), url = Bundle.module.url(forResource: "bit101", withExtension: "ics", subdirectory: "Fixtures")!
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "changes-on-every-export", with: UUID().uuidString)
        XCTAssertEqual(try ICSParser().parse(text), c)
    }
    func testOverlappingCourses() throws {
        var s = try snapshot(); let a = s.courses[0]
        let b = CourseOccurrence(title: "冲突课", start: a.start, end: a.end)
        s = ScheduleSnapshot(origin: s.origin, revision: 2, semester: s.semester, courses: s.courses + [b])
        XCTAssertEqual(ScheduleEngine.status(in: s, at: a.start).simultaneous.count, 2)
    }
    func testTimelineIncludesBoundariesAndMidnight() throws {
        let s = try snapshot(), dates = ScheduleEngine.timelineDates(in: s, from: date("2026-10-13T07:00:00"))
        XCTAssertTrue(dates.contains(s.courses[0].start)); XCTAssertTrue(dates.contains(s.courses[0].end))
        XCTAssertTrue(dates.contains(date("2026-10-14T00:00:00")))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
    }
    func testWeeklyRuleExclusionAndExtraDate() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:每周课程
        DTSTART;TZID=Asia/Shanghai:20261012T080000
        DTEND;TZID=Asia/Shanghai:20261012T090000
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4
        EXDATE;TZID=Asia/Shanghai:20261014T080000
        RDATE;TZID=Asia/Shanghai:20261016T080000
        END:VEVENT
        END:VCALENDAR
        """
        let c = try ICSParser().parse(text)
        XCTAssertEqual(c.count, 4); XCTAssertEqual(c.map(\.start), ["12", "16", "19", "21"].map { date("2026-10-\($0)T08:00:00") })
    }
    func testUnsupportedRecurrenceIsExplicitError() throws {
        let c = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:x\nDTSTART:20261012T080000\nDTEND:20261012T090000\nRRULE:FREQ=MONTHLY;COUNT=4\nEND:VEVENT\nEND:VCALENDAR"
        XCTAssertThrowsError(try ICSParser().parse(c))
    }
    func testUnfoldEscapeUTCAndAllDay() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:程序
         设计\\,实践
        DTSTART:20261013T000000Z
        DTEND:20261013T014000Z
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:节假日
        DTSTART;VALUE=DATE:20261013
        END:VEVENT
        END:VCALENDAR
        """
        let c = try ICSParser().parse(text)
        XCTAssertEqual(c.count, 1); XCTAssertEqual(c[0].title, "程序设计,实践")
        XCTAssertEqual(c[0].start, date("2026-10-13T08:00:00"))
        XCTAssertEqual(c[0].displayLocation, "地点待定")
    }
    func testBadDatesAndTruncatedCalendarRejected() {
        XCTAssertThrowsError(try ICSParser().parse("not an ICS"))
        XCTAssertThrowsError(try ICSParser().parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR"))
        let c = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:x\nDTSTART:20260230T080000\nDTEND:20260301T090000\nEND:VEVENT\nEND:VCALENDAR"
        XCTAssertThrowsError(try ICSParser().parse(c))
    }
    func testPersistenceAndCorruptData() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir), s = try snapshot()
        XCTAssertNil(try store.load()); try store.save(s); XCTAssertEqual(try store.load(), s)
        var corrupt = s; corrupt.courses[0].title = "被修改"
        XCTAssertThrowsError(try store.save(corrupt)); XCTAssertEqual(try store.load(), s)
    }
    func testStaleAndClearState() throws {
        let s = try snapshot()
        XCTAssertTrue(ScheduleEngine.status(in: s, at: date("2026-10-22T08:00:00")).stale)
        let clear = ScheduleSnapshot(origin: s.origin, revision: 2, semester: s.semester, courses: [], isCleared: true)
        XCTAssertEqual(ScheduleEngine.status(in: clear, at: Date()).phase, .needsImport)
    }
    func testSyncRejectsOldWrongOriginAndWrongHash() throws {
        let s = try snapshot()
        let next = ScheduleSnapshot(origin: "phone", revision: 2, semester: s.semester, courses: s.courses)
        XCTAssertTrue(SyncPolicy.accepts(next, current: s, expectedOrigin: "phone", expectedRevision: 2, expectedHash: next.contentHash))
        XCTAssertFalse(SyncPolicy.accepts(s, current: next, expectedOrigin: "phone", expectedRevision: 1, expectedHash: s.contentHash))
        XCTAssertFalse(SyncPolicy.accepts(next, current: s, expectedOrigin: "other", expectedRevision: 2, expectedHash: next.contentHash))
        XCTAssertFalse(SyncPolicy.accepts(next, current: s, expectedOrigin: "phone", expectedRevision: 2, expectedHash: "wrong"))
    }
    func testWeekUsesSchoolCalendar() throws {
        let s = try snapshot(); XCTAssertEqual(s.semester.week(at: date("2026-10-13T00:00:00")), 6)
        XCTAssertEqual(SchoolClock.monday(containing: date("2026-10-18T23:59:00")), date("2026-10-12T00:00:00"))
    }
    func testDemoValidAndClearlyMarked() throws {
        let s = DemoSchedule.make(at: date("2026-10-13T12:00:00"), origin: "demo", revision: 1)
        try s.validate(); XCTAssertTrue(s.isDemo); XCTAssertEqual(s.courses.count, 30)
    }
}
