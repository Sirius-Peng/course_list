import Foundation

public enum CoursePhase: String, Codable, Sendable { case current, upcoming, empty, needsImport, expired }
public struct CourseStatus: Equatable, Sendable {
    public var phase: CoursePhase
    public var course: CourseOccurrence?
    public var simultaneous: [CourseOccurrence]
    public var next: CourseOccurrence?
    public var stale: Bool
    public var heading: String {
        switch phase {
        case .current: "上课中"
        case .upcoming: "下一课"
        case .empty: "暂无后续课程"
        case .needsImport: "请导入课表"
        case .expired: "请更新课表"
        }
    }
}
public enum ScheduleEngine {
    public static func status(in snapshot: ScheduleSnapshot?, at now: Date) -> CourseStatus {
        guard let snapshot, !snapshot.isCleared else { return CourseStatus(phase: .needsImport, simultaneous: [], stale: false) }
        let stale = now.timeIntervalSince(snapshot.fetchedAt) > 7 * 86400
        guard now < snapshot.semester.end else { return CourseStatus(phase: .expired, simultaneous: [], stale: stale) }
        let current = snapshot.courses.filter { $0.start <= now && now < $0.end }
        let future = snapshot.courses.filter { $0.start > now }
        let next = future.first
        if let course = current.first {
            return CourseStatus(phase: .current, course: course, simultaneous: current, next: next, stale: stale)
        }
        if let next {
            return CourseStatus(phase: .upcoming, course: next, simultaneous: future.filter { $0.start == next.start }, next: next, stale: stale)
        }
        return CourseStatus(phase: .empty, simultaneous: [], stale: stale)
    }
    public static func courses(in snapshot: ScheduleSnapshot?, on date: Date) -> [CourseOccurrence] {
        snapshot?.courses.filter { SchoolClock.calendar.isDate($0.start, inSameDayAs: date) } ?? []
    }
    /// No networking: entries describe predictable schedule transitions.
    public static func timelineDates(in snapshot: ScheduleSnapshot?, from now: Date, hours: Int = 72) -> [Date] {
        let horizon = now.addingTimeInterval(Double(hours) * 3600)
        var dates: Set<Date> = [now, horizon]
        if let snapshot {
            for c in snapshot.courses {
                if c.start > now && c.start < horizon { dates.insert(c.start) }
                if c.end > now && c.end < horizon { dates.insert(c.end) }
            }
            if snapshot.semester.end > now && snapshot.semester.end < horizon { dates.insert(snapshot.semester.end) }
        }
        var midnight = SchoolClock.calendar.date(byAdding: .day, value: 1, to: SchoolClock.calendar.startOfDay(for: now))!
        while midnight < horizon { dates.insert(midnight); midnight = SchoolClock.calendar.date(byAdding: .day, value: 1, to: midnight)! }
        return dates.sorted()
    }
}

public enum SyncPolicy {
    public static func accepts(_ candidate: ScheduleSnapshot, current: ScheduleSnapshot?, expectedOrigin: String,
                               expectedRevision: Int64, expectedHash: String) -> Bool {
        guard (try? candidate.validate()) != nil, candidate.origin == expectedOrigin,
              candidate.revision == expectedRevision, candidate.contentHash == expectedHash else { return false }
        guard let current, current.origin == candidate.origin else { return true }
        return candidate.revision > current.revision || (candidate.revision == current.revision && candidate.contentHash == current.contentHash)
    }
}

public enum DemoSchedule {
    public static func make(at now: Date = Date(), origin: String, revision: Int64) -> ScheduleSnapshot {
        let cal = SchoolClock.calendar, monday = SchoolClock.monday(containing: now)
        let names = ["高等数学", "大学物理", "程序设计", "大学英语", "线性代数"]
        var courses: [CourseOccurrence] = []
        for day in 0..<14 where day % 7 < 5 {
            let date = cal.date(byAdding: .day, value: day, to: monday)!
            for hour in [8, 10, 14] {
                let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
                courses.append(CourseOccurrence(title: names[(day + hour) % names.count], location: "良乡理教楼 \(100 + day % 5 * 10 + hour)", start: start, end: start.addingTimeInterval(100 * 60), notes: "演示课程 · 非真实课表"))
            }
        }
        return ScheduleSnapshot(origin: origin, revision: revision, semester: Semester(name: "演示课表", firstMonday: monday, end: cal.date(byAdding: .day, value: 14, to: monday)!), courses: courses, isDemo: true)
    }
}
