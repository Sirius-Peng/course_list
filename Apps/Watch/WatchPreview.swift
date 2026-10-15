import Foundation
import ScheduleCore

/// Explicit Debug launch fixtures for layout QA. Never written, imported or transmitted.
struct WatchPreview {
    let date: Date
    let snapshot: ScheduleSnapshot?
    static let active: WatchPreview? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-WatchPreview"), args.indices.contains(i + 1) else { return nil }
        let kind = args[i + 1]
        guard ["current", "upcoming", "empty", "expired", "long", "needsImport"].contains(kind) else { return nil }
        let now = ISO8601DateFormatter().date(from: "2026-10-15T09:05:00+08:00")!
        if kind == "needsImport" { return WatchPreview(date: now, snapshot: nil) }
        let cal = SchoolClock.calendar
        let day = cal.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)! }
        let monday = SchoolClock.monday(containing: now)
        let semester = Semester(name: "界面演示", firstMonday: monday, end: cal.date(byAdding: .day, value: kind == "expired" ? 1 : 140, to: monday)!)
        var courses: [CourseOccurrence] = []
        if !["empty", "expired"].contains(kind) {
            courses.append(CourseOccurrence(title: kind == "long" ? "计算机组成原理与嵌入式系统设计综合实验" : "高等数学", location: kind == "long" ? "良乡校区文萃楼 E 区 301 综合实验室" : "良乡理教楼 201", start: kind == "upcoming" ? at(9, 20) : at(8), end: at(9, 40), notes: "演示课程 · 用于 Watch 界面验证\n请携带教材与笔记本。"))
            courses += [CourseOccurrence(title: "程序设计", location: "文萃楼 E301", start: at(10), end: at(11, 40)),
                        CourseOccurrence(title: "大学英语", location: "综合教学楼 402", start: at(14), end: at(15, 40)),
                        CourseOccurrence(title: "大学物理", location: "良乡理教楼 305", start: at(16), end: at(17, 40))]
        }
        return WatchPreview(date: now, snapshot: ScheduleSnapshot(origin: "watch-ui-preview", revision: 1, fetchedAt: now, semester: semester, courses: courses, isDemo: true))
        #else
        return nil
        #endif
    }()
}
