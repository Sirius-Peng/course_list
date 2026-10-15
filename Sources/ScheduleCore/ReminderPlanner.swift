import Foundation

public struct ReminderPreferences: Codable, Equatable, Sendable {
    public static let supportedMinutes = [5, 10, 15, 30]
    public var enabled: Bool
    public var leadMinutes: Int
    public init(enabled: Bool = false, leadMinutes: Int = 10) {
        self.enabled = enabled; self.leadMinutes = leadMinutes
    }
}
public struct PlannedCourseReminder: Equatable, Sendable, Identifiable {
    public var id: String
    public var courseID: String
    public var fireDate: Date
    public var title: String
    public var body: String
}
public enum ReminderPlanner {
    public static let identifierPrefix = "course-reminder."
    /// Keep a conservative rolling queue, instead of enqueueing an entire semester.
    public static func plan(snapshot: ScheduleSnapshot?, preferences: ReminderPreferences,
                            now: Date, capacity: Int = 60) -> [PlannedCourseReminder] {
        guard preferences.enabled, ReminderPreferences.supportedMinutes.contains(preferences.leadMinutes),
              let snapshot, !snapshot.isCleared, now < snapshot.semester.end, capacity > 0 else { return [] }
        let reminders = snapshot.courses.compactMap { course -> PlannedCourseReminder? in
            let fireDate = course.start.addingTimeInterval(-Double(preferences.leadMinutes * 60))
            guard fireDate > now else { return nil }
            return PlannedCourseReminder(id: identifierPrefix + course.id, courseID: course.id, fireDate: fireDate,
                title: "\(preferences.leadMinutes)分钟后上课\(snapshot.isDemo ? " · 演示" : "")",
                body: "\(course.title)\n\(course.timeRange) · \(course.displayLocation)")
        }.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        return Array(reminders.prefix(min(capacity, 60)))
    }
}
