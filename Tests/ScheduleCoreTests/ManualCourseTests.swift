import XCTest
import CryptoKit
@testable import ScheduleCore

final class ManualCourseTests: XCTestCase {
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "+08:00")! }
    var semester: Semester { Semester(name: "秋季", firstMonday: date("2026-10-12T00:00:00"), end: date("2027-01-01T00:00:00")) }
    var draft: ManualCourseDraft { ManualCourseDraft(title: "  自选课程 \n", location: " A201 ", start: date("2026-10-15T08:00:00"), end: date("2026-10-15T09:40:00"), notes: " 带电脑 ") }
    func added(_ draft: ManualCourseDraft? = nil, to current: ScheduleSnapshot? = nil) throws -> ScheduleSnapshot {
        try ManualCourseEditor.adding(draft ?? self.draft, to: current, semester: semester, origin: "phone", revision: (current?.revision ?? 0) + 1)
    }
    func testSingleManualCourseCreatesValidPersonalSnapshot() throws {
        let s = try added(), c = try XCTUnwrap(s.courses.first)
        XCTAssertEqual(c.title, "自选课程"); XCTAssertEqual(c.location, "A201"); XCTAssertEqual(c.notes, "带电脑")
        XCTAssertFalse(s.isDemo); XCTAssertFalse(s.isCleared); XCTAssertEqual(s.manualCourseIDs, [c.id])
        XCTAssertEqual(try ScheduleSnapshot.decode(s.encoded()), s)
    }
    func testWeeklyIncludesEndDayAndPreservesTime() throws {
        var d = draft; d.weeklyThrough = date("2026-11-05T00:00:00")
        let s = try added(d)
        XCTAssertEqual(s.courses.count, 4)
        XCTAssertEqual(s.courses.map { SchoolClock.format($0.start, "M/d HH:mm") }, ["10/15 08:00", "10/22 08:00", "10/29 08:00", "11/5 08:00"])
        XCTAssertEqual(Set(s.courses.map(\.id)).count, 4)
        XCTAssertTrue(s.courses.allSatisfy { $0.timeRange == "08:00–09:40" })
    }
    func testWeeklyStopsBeforeNextOccurrence() throws {
        var d = draft; d.weeklyThrough = date("2026-10-21T23:59:59")
        XCTAssertEqual(try added(d).courses.count, 1)
    }
    func testInvalidTextAndTimeRejected() {
        var d = draft; d.title = " \n"; XCTAssertThrowsError(try added(d))
        d = draft; d.title = String(repeating: "x", count: 201); XCTAssertThrowsError(try added(d))
        d = draft; d.end = d.start; XCTAssertThrowsError(try added(d))
        d = draft; d.end = date("2026-10-16T00:30:00"); XCTAssertThrowsError(try added(d))
        d = draft; d.weeklyThrough = date("2026-10-14T00:00:00"); XCTAssertThrowsError(try added(d))
        d = draft; d.weeklyThrough = date("2028-10-15T00:00:00"); XCTAssertThrowsError(try added(d))
    }
    func testOutsideSemesterRejectedWithoutChangingOriginal() throws {
        let old = try added(); let data = try old.encoded()
        var d = draft; d.start = date("2027-01-04T08:00:00"); d.end = d.start.addingTimeInterval(3600)
        // Compare the persisted state, not unspecified JSON key ordering.
        XCTAssertThrowsError(try added(d, to: old)); XCTAssertEqual(try ScheduleSnapshot.decode(old.encoded()), try ScheduleSnapshot.decode(data))
    }
    func testAppendKeepsImportedCourseAndFreshness() throws {
        let c = CourseOccurrence(title: "学校课程", start: date("2026-10-16T08:00:00"), end: date("2026-10-16T09:00:00"))
        let old = ScheduleSnapshot(origin: "phone", revision: 2, fetchedAt: date("2026-10-13T00:00:00"), semester: semester, courses: [c])
        let s = try added(to: old)
        XCTAssertTrue(s.courses.contains(c)); XCTAssertEqual(s.courses.count, 2); XCTAssertEqual(s.fetchedAt, old.fetchedAt)
        XCTAssertEqual(ReminderPlanner.plan(snapshot: s, preferences: .init(enabled: true), now: date("2026-10-14T00:00:00")).count, 2)
    }
    func testImportedRefreshRetainsManualAndAvoidsDuplicate() throws {
        let s = try added(); var schoolCopy = s.courses[0]; schoolCopy.id = "school-id"
        let extra = CourseOccurrence(title: "学校课程", start: date("2026-10-16T08:00:00"), end: date("2026-10-16T09:00:00"))
        let next = try ManualCourseEditor.replacingImported([schoolCopy, extra], semester: semester, current: s, origin: "phone", revision: 3)
        XCTAssertEqual(next.courses.count, 2); XCTAssertEqual(next.manualCourseIDs, s.manualCourseIDs)
        XCTAssertTrue(next.courses.contains(s.courses[0])); XCTAssertFalse(next.courses.contains(schoolCopy))
        var newTerm = semester; newTerm.firstMonday = date("2026-11-02T00:00:00")
        XCTAssertThrowsError(try ManualCourseEditor.replacingImported([], semester: newTerm, current: s, origin: "phone", revision: 4))
    }
    func testDuplicateManualOrImportedRejected() throws {
        let s = try added(); XCTAssertThrowsError(try added(to: s))
        let imported = CourseOccurrence(title: "自选课程", location: "A201", start: draft.start, end: draft.end)
        let old = ScheduleSnapshot(origin: "phone", revision: 1, semester: semester, courses: [imported])
        XCTAssertThrowsError(try added(to: old))
    }
    func testDeleteOnlyOneOccurrenceAndRejectImportedDeletion() throws {
        var d = draft; d.weeklyThrough = date("2026-10-29T00:00:00")
        let s = try added(d), id = s.courses[1].id
        let next = try ManualCourseEditor.removing(id, from: s, origin: "phone", revision: 2)
        XCTAssertEqual(next.courses.count, 2); XCTAssertFalse(next.courses.contains { $0.id == id })
        XCTAssertThrowsError(try ManualCourseEditor.removing("not-manual", from: s, origin: "phone", revision: 2))
    }
    func testLegacyJSONKeepsOriginalPayloadHash() throws {
        let course = CourseOccurrence(title: "旧课程", start: draft.start, end: draft.end)
        let s = ScheduleSnapshot(origin: "phone", revision: 1, semester: semester, courses: [course])
        let data = try s.encoded(), object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["manualCourseIDs"])
        struct LegacyPayload: Encodable { var semester: Semester; var courses: [CourseOccurrence]; var isDemo: Bool; var isCleared: Bool }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let legacy = try encoder.encode(LegacyPayload(semester: semester, courses: [course], isDemo: false, isCleared: false))
        XCTAssertEqual(s.contentHash, SHA256.hash(data: legacy).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try ScheduleSnapshot.decode(data), s)
        var tampered = try added(); tampered.manualCourseIDs = nil; XCTAssertThrowsError(try tampered.validate())
    }
    func testConflictCountUsesActualOverlapNotAdjacentEdges() throws {
        let s = try added()
        var d = draft; d.title = "其他课程"; d.start = date("2026-10-15T09:30:00"); d.end = date("2026-10-15T10:00:00")
        XCTAssertEqual(try ManualCourseEditor.conflictCount(for: d, in: s), 1)
        d.start = date("2026-10-15T09:40:00"); XCTAssertEqual(try ManualCourseEditor.conflictCount(for: d, in: s), 0)
    }
    func testAddAfterClearRemovesTombstoneAndRestoresSchedule() throws {
        let old = ScheduleSnapshot(origin: "phone", revision: 4, semester: semester, courses: [], isCleared: true)
        let s = try added(to: old); XCTAssertFalse(s.isCleared); XCTAssertEqual(s.courses.count, 1)
        XCTAssertEqual(ScheduleEngine.status(in: s, at: draft.start).phase, .current)
        let next = try ManualCourseEditor.removing(s.courses[0].id, from: s, origin: "phone", revision: 6)
        XCTAssertTrue(next.courses.isEmpty); XCTAssertNil(next.manualCourseIDs); try next.validate()
    }
}
