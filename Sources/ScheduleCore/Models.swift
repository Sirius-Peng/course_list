import Foundation
import CryptoKit

public enum ScheduleError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

public enum SchoolClock {
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }
    public static func monday(containing date: Date) -> Date {
        let cal = calendar
        let day = cal.startOfDay(for: date)
        let offset = (cal.component(.weekday, from: day) + 5) % 7
        return cal.date(byAdding: .day, value: -offset, to: day)!
    }
    public static func time(_ date: Date) -> String { format(date, "HH:mm") }
    public static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

public struct Semester: Codable, Equatable, Sendable {
    public var name: String
    public var firstMonday: Date
    public var end: Date
    public init(name: String, firstMonday: Date, end: Date) {
        self.name = name; self.firstMonday = firstMonday; self.end = end
    }
    public func week(at date: Date) -> Int {
        let days = SchoolClock.calendar.dateComponents([.day], from: firstMonday, to: SchoolClock.calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7)) + 1
    }
}

public struct CourseOccurrence: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var location: String
    public var start: Date
    public var end: Date
    public var notes: String
    public init(title: String, location: String = "", start: Date, end: Date, notes: String = "") {
        self.title = title; self.location = location; self.start = start; self.end = end; self.notes = notes
        // Ignore unstable upstream UID. Refresh always replaces a whole semester.
        self.id = Self.fingerprint([title, location, String(start.timeIntervalSince1970), String(end.timeIntervalSince1970)].joined(separator: "\u{1F}"))
    }
    public var displayLocation: String { location.isEmpty ? "地点待定" : location.components(separatedBy: "\n").first ?? location }
    public var timeRange: String { "\(SchoolClock.time(start))–\(SchoolClock.time(end))" }
    public static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ScheduleSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var origin: String
    public var revision: Int64
    public var fetchedAt: Date
    public var semester: Semester
    public var courses: [CourseOccurrence]
    public var isDemo: Bool
    public var isCleared: Bool
    public var contentHash: String
    /// Absent in older snapshots; imported refreshes retain these occurrences.
    public var manualCourseIDs: [String]?

    public init(origin: String, revision: Int64, fetchedAt: Date = Date(), semester: Semester,
                courses: [CourseOccurrence], isDemo: Bool = false, isCleared: Bool = false, manualCourseIDs: [String] = []) {
        self.origin = origin; self.revision = revision; self.fetchedAt = fetchedAt; self.semester = semester
        self.courses = courses.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        self.isDemo = isDemo; self.isCleared = isCleared
        self.manualCourseIDs = manualCourseIDs.isEmpty ? nil : manualCourseIDs.sorted()
        self.contentHash = Self.hash(semester: semester, courses: self.courses, isDemo: isDemo, isCleared: isCleared, manualCourseIDs: self.manualCourseIDs)
    }
    private struct Payload: Codable {
        var semester: Semester; var courses: [CourseOccurrence]; var isDemo: Bool; var isCleared: Bool
        var manualCourseIDs: [String]?
    }
    private static func hash(semester: Semester, courses: [CourseOccurrence], isDemo: Bool, isCleared: Bool, manualCourseIDs: [String]?) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(Payload(semester: semester, courses: courses, isDemo: isDemo, isCleared: isCleared, manualCourseIDs: manualCourseIDs))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw ScheduleError.invalid("课表数据版本不匹配，请更新 App") }
        guard !origin.isEmpty, revision > 0, semester.end > semester.firstMonday,
              semester.end.timeIntervalSince(semester.firstMonday) < 370 * 86400,
              courses.count <= 5000 else { throw ScheduleError.invalid("课表元数据无效") }
        guard courses.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start
            && $0.start >= semester.firstMonday && $0.end <= semester.end && $0.end.timeIntervalSince($0.start) <= 86400 }) else {
            throw ScheduleError.invalid("课程日期超出学期或时间区间无效，请检查学期设置")
        }
        guard !isCleared || courses.isEmpty else { throw ScheduleError.invalid("清空记录含有课程") }
        guard Set(courses.map(\.id)).count == courses.count else { throw ScheduleError.invalid("课表含重复课程") }
        let manual = manualCourseIDs ?? []
        guard Set(manual).count == manual.count, Set(manual).isSubset(of: Set(courses.map(\.id))) else {
            throw ScheduleError.invalid("手动课程标识无效")
        }
        guard contentHash == Self.hash(semester: semester, courses: courses, isDemo: isDemo, isCleared: isCleared, manualCourseIDs: self.manualCourseIDs) else {
            throw ScheduleError.invalid("课表内容校验失败")
        }
    }
    public func encoded() throws -> Data { try validate(); return try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4_000_000 else { throw ScheduleError.invalid("课表文件过大") }
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
}
