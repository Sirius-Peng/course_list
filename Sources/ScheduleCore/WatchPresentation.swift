import Foundation

/// Display-only helpers: changing the watch UI never changes the stored timetable.
public enum WatchPresentation {
    public static func progress(for course: CourseOccurrence, at date: Date) -> Double {
        let duration = course.end.timeIntervalSince(course.start)
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(course.start) / duration))
    }
    public static func remainingText(for course: CourseOccurrence, at date: Date) -> String {
        let minutes = Int(ceil(course.end.timeIntervalSince(date) / 60))
        return minutes > 0 ? "还有\(durationText(minutes))下课" : "即将下课"
    }
    public static func upcomingText(for course: CourseOccurrence, at date: Date) -> String {
        guard SchoolClock.calendar.isDate(course.start, inSameDayAs: date) else {
            return SchoolClock.format(course.start, "M月d日 HH:mm") + " 上课"
        }
        let minutes = Int(ceil(course.start.timeIntervalSince(date) / 60))
        return minutes > 0 ? "\(durationText(minutes))后上课" : "即将上课"
    }
    public static func paletteIndex(for title: String) -> Int {
        (Int(CourseOccurrence.fingerprint(title).prefix(2), radix: 16) ?? 0) % 4
    }
    private static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分钟" }
        let hours = minutes / 60, remainder = minutes % 60
        return remainder == 0 ? "\(hours)小时" : "\(hours)小时\(remainder)分钟"
    }
}
