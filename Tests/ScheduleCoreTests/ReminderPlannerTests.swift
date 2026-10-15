import XCTest
@testable import ScheduleCore

final class ReminderPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(courses: [CourseOccurrence], cleared: Bool = false) -> ScheduleSnapshot {
        ScheduleSnapshot(origin: "fixture", revision: 1,
            semester: Semester(name: "fixture", firstMonday: now.addingTimeInterval(-86400), end: now.addingTimeInterval(30 * 86400)),
            courses: courses, isCleared: cleared)
    }
    private func course(minutes: Int, name: String = "课程") -> CourseOccurrence {
        CourseOccurrence(title: name, location: "教室201", start: now.addingTimeInterval(Double(minutes * 60)),
                         end: now.addingTimeInterval(Double((minutes + 90) * 60)))
    }
    func testDisabledAndMissingScheduleHaveNoReminders() {
        XCTAssertTrue(ReminderPlanner.plan(snapshot: snapshot(courses: [course(minutes: 30)]), preferences: .init(), now: now).isEmpty)
        XCTAssertTrue(ReminderPlanner.plan(snapshot: nil, preferences: .init(enabled: true), now: now).isEmpty)
        XCTAssertTrue(ReminderPlanner.plan(snapshot: snapshot(courses: [], cleared: true), preferences: .init(enabled: true), now: now).isEmpty)
    }
    func testCorrectLeadTimeAndMessage() {
        let c = course(minutes: 30, name: "高等数学")
        let r = ReminderPlanner.plan(snapshot: snapshot(courses: [c]), preferences: .init(enabled: true, leadMinutes: 10), now: now)
        XCTAssertEqual(r.count, 1); XCTAssertEqual(r[0].fireDate, now.addingTimeInterval(20 * 60))
        XCTAssertEqual(r[0].courseID, c.id); XCTAssertTrue(r[0].body.contains("高等数学"))
        XCTAssertTrue(r[0].body.contains("教室201")); XCTAssertEqual(r[0].title, "10分钟后上课")
    }
    func testNoPastOrImmediateBackfill() {
        let s = snapshot(courses: [course(minutes: -30), course(minutes: 5), course(minutes: 10), course(minutes: 11)])
        let r = ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true, leadMinutes: 10), now: now)
        XCTAssertEqual(r.count, 1); XCTAssertEqual(r[0].fireDate, now.addingTimeInterval(60))
    }
    func testCapacityAndStableOrdering() {
        let s = snapshot(courses: (0..<100).map { course(minutes: 30 + $0 * 90, name: "课程\($0)") })
        let r = ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true), now: now)
        XCTAssertEqual(r.count, 60)
        XCTAssertEqual(r.map(\.fireDate), r.map(\.fireDate).sorted())
        XCTAssertEqual(ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true), now: now, capacity: 3).count, 3)
    }
    func testChangedLeadTimeKeepsIdentifierAndReschedules() {
        let s = snapshot(courses: [course(minutes: 30)])
        let a = ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true, leadMinutes: 5), now: now)
        let b = ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true, leadMinutes: 15), now: now)
        XCTAssertEqual(a[0].id, b[0].id); XCTAssertEqual(a[0].fireDate.timeIntervalSince(b[0].fireDate), 600)
    }
    func testInvalidPreferencesAndDemoLabel() {
        let s = snapshot(courses: [course(minutes: 30)])
        XCTAssertTrue(ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true, leadMinutes: -1), now: now).isEmpty)
        let demo = ScheduleSnapshot(origin: s.origin, revision: s.revision, semester: s.semester, courses: s.courses, isDemo: true)
        XCTAssertTrue(ReminderPlanner.plan(snapshot: demo, preferences: .init(enabled: true), now: now)[0].title.contains("演示"))
    }
    func testExpiredAndZeroCapacity() {
        let s = snapshot(courses: [course(minutes: 30)])
        XCTAssertTrue(ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true), now: s.semester.end).isEmpty)
        XCTAssertTrue(ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true), now: now, capacity: 0).isEmpty)
    }
}
