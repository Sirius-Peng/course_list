import Foundation

public struct ManualCourseDraft: Sendable {
    public var title: String
    public var location: String
    public var start: Date
    public var end: Date
    public var notes: String
    /// Inclusive final day, using the school's calendar. nil means a single occurrence.
    public var weeklyThrough: Date?
    public init(title: String, location: String = "", start: Date, end: Date, notes: String = "", weeklyThrough: Date? = nil) {
        self.title = title; self.location = location; self.start = start; self.end = end
        self.notes = notes; self.weeklyThrough = weeklyThrough
    }
    public func occurrences() throws -> [CourseOccurrence] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200, location.count <= 300, notes.count <= 2000 else {
            throw ScheduleError.invalid("请填写课程名称（最多 200 字），地点最多 300 字，备注最多 2000 字")
        }
        let cal = SchoolClock.calendar
        guard end > start, cal.isDate(start, inSameDayAs: end) else {
            throw ScheduleError.invalid("下课时间须晚于上课时间，且在同一天内")
        }
        var starts = [start]
        if let until = weeklyThrough {
            let lastDay = cal.startOfDay(for: until)
            guard lastDay >= cal.startOfDay(for: start), lastDay.timeIntervalSince(start) < 370 * 86400 else {
                throw ScheduleError.invalid("重复截止日期须不早于首次上课日期，且在一年内")
            }
            var next = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            while cal.startOfDay(for: next) <= lastDay {
                starts.append(next); next = cal.date(byAdding: .weekOfYear, value: 1, to: next)!
            }
        }
        let series = UUID().uuidString
        return starts.enumerated().map { index, start in
            var course = CourseOccurrence(title: title, location: location, start: start,
                end: start.addingTimeInterval(end.timeIntervalSince(self.start)), notes: notes)
            course.id = "manual.\(series).\(index)"
            return course
        }
    }
}

public enum ManualCourseEditor {
    public static func adding(_ draft: ManualCourseDraft, to current: ScheduleSnapshot?, semester: Semester,
                              origin: String, revision: Int64, now: Date = Date()) throws -> ScheduleSnapshot {
        let additions = try draft.occurrences()
        let old = current?.isCleared == false ? current?.courses ?? [] : []
        let keys = Set(old.map(key))
        guard !additions.contains(where: { keys.contains(key($0)) }) else {
            throw ScheduleError.invalid("已有相同名称、地点和时间的课程，请勿重复添加")
        }
        let result = ScheduleSnapshot(origin: origin, revision: revision, fetchedAt: current?.fetchedAt ?? now,
            semester: current?.semester ?? semester, courses: old + additions,
            manualCourseIDs: (current?.manualCourseIDs ?? []) + additions.map(\.id))
        try result.validate(); return result
    }
    public static func replacingImported(_ courses: [CourseOccurrence], semester: Semester, current: ScheduleSnapshot?,
                                         origin: String, revision: Int64) throws -> ScheduleSnapshot {
        let ids = Set(current?.manualCourseIDs ?? [])
        let manual = (current?.courses ?? []).filter { ids.contains($0.id) }
        // Prefer the user's manually entered occurrence if the school now exports the same class.
        let keys = Set(manual.map(key))
        let imported = courses.filter { !keys.contains(key($0)) }
        let result = ScheduleSnapshot(origin: origin, revision: revision, semester: semester, courses: imported + manual,
            manualCourseIDs: manual.map(\.id))
        do { try result.validate() }
        catch {
            if manual.contains(where: { $0.start < semester.firstMonday || $0.end > semester.end }) {
                throw ScheduleError.invalid("手动课程超出导入学期，请调整学期范围后再导入；原课表已保留")
            }
            throw error
        }
        return result
    }
    public static func removing(_ id: String, from current: ScheduleSnapshot, origin: String, revision: Int64) throws -> ScheduleSnapshot {
        guard (current.manualCourseIDs ?? []).contains(id) else { throw ScheduleError.invalid("仅可在此删除手动添加的课程") }
        let result = ScheduleSnapshot(origin: origin, revision: revision, fetchedAt: current.fetchedAt,
            semester: current.semester, courses: current.courses.filter { $0.id != id },
            manualCourseIDs: (current.manualCourseIDs ?? []).filter { $0 != id })
        try result.validate(); return result
    }
    public static func conflictCount(for draft: ManualCourseDraft, in snapshot: ScheduleSnapshot?) throws -> Int {
        let additions = try draft.occurrences()
        return (snapshot?.courses ?? []).filter { old in additions.contains { $0.start < old.end && $0.end > old.start } }.count
    }
    private static func key(_ c: CourseOccurrence) -> String {
        CourseOccurrence.fingerprint([c.title, c.location, String(c.start.timeIntervalSince1970), String(c.end.timeIntervalSince1970)].joined(separator: "\u{1F}"))
    }
}
