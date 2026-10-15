#if os(watchOS)
import SwiftUI
import WidgetKit
import ScheduleCore

/// Native watch-face slot layouts. Never applies the phone Lock Screen's typography.
struct WatchComplicationView: View {
    let entry: CourseEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.isLuminanceReduced) private var dimmed
    private var accent: Color {
        guard renderingMode == .fullColor else { return .white }
        return entry.status.phase == .current ? Color(red: 0.31, green: 0.93, blue: 0.75) : Color(red: 1, green: 0.77, blue: 0.36)
    }
    private var ink: Color { renderingMode == .fullColor && showsBackground ? .white : .primary }
    private var stateText: String {
        guard let course = entry.status.course else { return entry.storageError ?? entry.status.heading }
        if entry.status.phase == .current { return "上课中" }
        return SchoolClock.calendar.isDate(course.start, inSameDayAs: entry.date) ? "下一课" : SchoolClock.format(course.start, "M/d")
    }
    private var courseLabel: String {
        let text = entry.status.course?.title ?? entry.storageError ?? entry.status.heading
        return text + (entry.snapshot?.isDemo == true ? " · 演示" : "")
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .privacySensitive().accessibilityElement(children: .combine)
    }
    private var rectangular: some View {
        GeometryReader { geometry in
            let roomy = geometry.size.height >= 62
            let showProgress = geometry.size.height >= 53 && entry.status.phase == .current
            HStack(spacing: 6) {
                Capsule().fill(accent).frame(width: 3).widgetAccentable()
                VStack(alignment: .leading, spacing: roomy ? 3 : 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.status.course?.title ?? (entry.storageError == nil ? emptyTitle : "打开 App 更新"))
                            .font(.system(size: roomy ? 18 : 15, weight: .bold, design: .rounded))
                            .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                        if entry.snapshot?.isDemo == true { Text("演示").font(.system(size: 8, weight: .medium)).fixedSize().foregroundStyle(accent).widgetAccentable() }
                    }
                    if let course = entry.status.course {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(course.timeRange).font(.system(size: roomy ? 13 : 11, weight: .semibold, design: .rounded))
                                .monospacedDigit().foregroundStyle(ink.opacity(0.95)).lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
                            Spacer(minLength: 0)
                            Text(stateText).font(.system(size: roomy ? 10 : 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent).lineLimit(1).fixedSize(horizontal: true, vertical: false).widgetAccentable()
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(accent).widgetAccentable()
                            Text(course.displayLocation).foregroundStyle(ink.opacity(0.72)).lineLimit(1).minimumScaleFactor(0.75)
                        }.font(.system(size: roomy ? 11 : 10, weight: .medium))
                        if showProgress {
                            ProgressView(timerInterval: course.start...course.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                                .progressViewStyle(.linear).tint(accent).scaleEffect(x: 1, y: 0.25)
                                .frame(height: 3).clipped().padding(.top, 1).widgetAccentable().accessibilityHidden(true)
                        }
                    } else {
                        Text(emptySubtitle).font(.system(size: roomy ? 12 : 10, weight: .medium)).foregroundStyle(ink.opacity(0.65))
                            .lineLimit(2).minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2).padding(.horizontal, 2)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle().strokeBorder(ink.opacity(dimmed ? 0.10 : 0.17), lineWidth: 4)
            if let course = entry.status.course {
                if entry.status.phase == .current {
                    Circle().strokeBorder(accent, lineWidth: 3).widgetAccentable()
                    VStack(spacing: 1) {
                        Text(timerInterval: course.start...course.end, countsDown: true, showsHours: false)
                            .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                            .multilineTextAlignment(.center).minimumScaleFactor(0.7)
                        Text("下课倒计时").font(.system(size: 6.5, weight: .medium))
                    }.foregroundStyle(ink).padding(7)
                } else {
                    Circle().strokeBorder(accent, lineWidth: 3).widgetAccentable()
                    VStack(spacing: 1) {
                        Text(stateText == "下一课" ? "下一课" : stateText).font(.system(size: 8, weight: .medium)).foregroundStyle(accent).widgetAccentable()
                        Text(SchoolClock.time(course.start)).font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(ink)
                    }.padding(6)
                }
            } else {
                Image(systemName: entry.status.phase == .empty ? "leaf.fill" : "calendar.badge.exclamationmark")
                    .font(.system(size: 19, weight: .medium)).foregroundStyle(accent).widgetAccentable()
            }
        }
        .clipShape(Circle())
        .widgetLabel { Text(courseLabel).font(.caption2) }
    }
    private var inline: some View {
        Group {
            if let course = entry.status.course {
                Label("\(entry.status.phase == .current ? "上课中" : SchoolClock.format(course.start, "M/d HH:mm")) \(course.title)\(entry.snapshot?.isDemo == true ? "·演示" : "")", systemImage: "book.closed.fill")
            } else { Label(entry.storageError ?? entry.status.heading, systemImage: "calendar") }
        }.foregroundStyle(accent)
    }
    private var emptyTitle: String {
        switch entry.status.phase {
        case .needsImport: "课表待同步"
        case .expired: "新学期待开启"
        default: "暂时无课"
        }
    }
    private var emptySubtitle: String {
        if let error = entry.storageError { return error }
        return switch entry.status.phase {
        case .needsImport: "打开 iPhone 添加课程"
        case .expired: "请在 iPhone 更新课表"
        default: "留点时间给自己"
        }
    }
}
struct WatchComplicationBackground: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        if family == .accessoryRectangular && renderingMode == .fullColor {
            LinearGradient(colors: [Color(red: 0.06, green: 0.23, blue: 0.25), Color(red: 0.025, green: 0.10, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(dimmed ? 0.45 : 1)
        } else { Color.clear }
    }
}
#endif
