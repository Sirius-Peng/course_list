import WidgetKit
import SwiftUI
import ScheduleCore

struct CourseEntry: TimelineEntry {
    var date: Date
    var snapshot: ScheduleSnapshot?
    var storageError: String?
    var status: CourseStatus { ScheduleEngine.status(in: snapshot, at: date) }
}
struct CourseProvider: TimelineProvider {
    func placeholder(in context: Context) -> CourseEntry {
        CourseEntry(date: Date(), snapshot: DemoSchedule.make(origin: "preview", revision: 1))
    }
    func getSnapshot(in context: Context, completion: @escaping (CourseEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        completion(load(at: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseEntry>) -> Void) {
        let now = Date(), current = load(at: now)
        let dates = ScheduleEngine.timelineDates(in: current.snapshot, from: now)
        let entries = dates.map { CourseEntry(date: $0, snapshot: current.snapshot, storageError: current.storageError) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3600))))
    }
    private func load(at date: Date) -> CourseEntry {
        do { return CourseEntry(date: date, snapshot: try PlatformStore.make().load()) }
        catch { return CourseEntry(date: date, storageError: "打开 App 更新课表") }
    }
}
struct CourseStatusWidget: Widget {
    let kind = "CourseStatus"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CourseProvider()) { entry in
            #if os(watchOS)
            WatchComplicationView(entry: entry)
                .containerBackground(for: .widget) { WatchComplicationBackground() }
                .widgetURL(widgetURL(for: entry))
            #else
            CourseWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(widgetURL(for: entry))
            #endif
        }
        #if os(watchOS)
        .contentMarginsDisabled()
        #endif
        .configurationDisplayName("课表")
        .description("上课时显示当前课程，空闲时显示下一课程的时间和地点。")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
    private func widgetURL(for entry: CourseEntry) -> URL? {
        var parts = URLComponents(); parts.scheme = "courselist"; parts.host = "course"
        if let course = entry.status.course { parts.queryItems = [URLQueryItem(name: "id", value: course.id)] }
        return parts.url
    }
}
struct CourseWidgetView: View {
    let entry: CourseEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .foregroundStyle(renderingMode == .fullColor ? Color.primary : Color.white)
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }
    private var heading: String {
        if let error = entry.storageError { return error }
        return entry.status.heading + (entry.snapshot?.isDemo == true ? " · 演示" : "")
    }
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let course = entry.status.course {
                HStack(spacing: 4) {
                    Image(systemName: entry.status.phase == .current ? "book.closed.fill" : "clock").widgetAccentable()
                    Text(course.title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(spacing: 4) {
                    Text(course.timeRange).monospacedDigit()
                    if !SchoolClock.calendar.isDate(course.start, inSameDayAs: entry.date) {
                        Text(SchoolClock.format(course.start, "M/d"))
                    } else { Text(entry.status.phase == .current ? "上课中" : "下一课") }
                }.font(.caption).lineLimit(1)
                Text(course.displayLocation + (entry.snapshot?.isDemo == true ? " · 演示" : ""))
                    .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Label(heading, systemImage: "calendar").font(.headline).lineLimit(1)
                Text("打开 App 查看课表").font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let course = entry.status.course {
                VStack(spacing: 2) {
                    if entry.status.phase == .current {
                        ProgressView(timerInterval: course.start...course.end, countsDown: false).progressViewStyle(.circular)
                            .labelsHidden().widgetAccentable()
                    } else {
                        Image(systemName: "calendar").font(.caption).widgetAccentable()
                        Text(SchoolClock.time(course.start)).font(.caption.bold()).monospacedDigit()
                    }
                }
            } else { Image(systemName: "calendar.badge.exclamationmark") }
        }
        .widgetLabel { Text(entry.status.course?.title ?? heading) }
    }
    private var inline: some View {
        Group {
            if let course = entry.status.course {
                Label("\(entry.status.phase == .current ? "上课中" : SchoolClock.format(course.start, "M/d HH:mm")) \(course.title)\(entry.snapshot?.isDemo == true ? "·演示" : "")", systemImage: "book.closed")
            } else { Label(heading, systemImage: "calendar") }
        }
    }
}
@main struct CourseWidgetBundle: WidgetBundle {
    var body: some Widget { CourseStatusWidget() }
}
#Preview(as: .accessoryRectangular) { CourseStatusWidget() } timeline: {
    CourseEntry(date: Date(), snapshot: DemoSchedule.make(origin: "preview", revision: 1))
}
