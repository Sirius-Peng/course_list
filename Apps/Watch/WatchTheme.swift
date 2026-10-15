import SwiftUI
import ScheduleCore

// Watch-only components keep the phone and Lock Screen's layout unchanged.
enum WatchTheme {
    static let ink = Color(red: 0.025, green: 0.09, blue: 0.13)
    static let mint = Color(red: 0.52, green: 0.96, blue: 0.78)
    static let cream = Color(red: 0.95, green: 0.99, blue: 0.96)
    static let amber = Color(red: 1, green: 0.80, blue: 0.43)
    static let palette = [mint, Color(red: 0.58, green: 0.79, blue: 1),
                          Color(red: 0.79, green: 0.69, blue: 1), amber]
    static func accent(for course: CourseOccurrence) -> Color { palette[WatchPresentation.paletteIndex(for: course.title)] }
}
struct WatchBackdrop: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        LinearGradient(colors: [Color(red: 0.06, green: 0.24, blue: 0.28), WatchTheme.ink,
                                Color(red: 0.04, green: 0.14, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(WatchTheme.mint.opacity(dimmed ? 0 : 0.10)).frame(width: 180, height: 180)
                    .blur(radius: 45).offset(x: 80, y: -80)
            }
            .overlay(dimmed ? Color.black.opacity(0.45) : Color.clear)
            .ignoresSafeArea().accessibilityHidden(true)
    }
}
struct WatchPhasePill: View {
    let title: String
    let color: Color
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: compact ? 9 : 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color).padding(.horizontal, compact ? 7 : 8).padding(.vertical, compact ? 4 : 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}
struct WatchCourseHero: View {
    let status: CourseStatus
    let snapshot: ScheduleSnapshot?
    let date: Date
    let minimumHeight: CGFloat
    let compact: Bool
    @ScaledMetric(relativeTo: .title2) private var titleSize = 25
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 4) {
                WatchPhasePill(title: status.phase == .current ? "正在上课" : "下一节课", color: status.phase == .current ? WatchTheme.mint : WatchTheme.amber, compact: compact)
                Spacer(minLength: 0)
                if snapshot?.isDemo == true { Text("演示").font(.system(size: 10, weight: .medium)).foregroundStyle(WatchTheme.amber) }
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            }
            if let course = status.course {
                Text(course.title).font(.system(size: titleSize * (compact ? 0.88 : 1), weight: .bold, design: .rounded))
                    .tracking(-0.6).lineLimit(3).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true).foregroundStyle(WatchTheme.cream)
                Label(course.timeRange, systemImage: "clock")
                    .font(.system(size: compact ? 14 : 16, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92)).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(WatchTheme.mint)
                    Text(course.displayLocation).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: compact ? 10.5 : 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 0)
                if status.phase == .current {
                    VStack(spacing: compact ? 5 : 7) {
                        HStack {
                            Text("课堂进度").foregroundStyle(.white.opacity(0.55))
                            Spacer(minLength: 2)
                            Text(WatchPresentation.remainingText(for: course, at: date)).foregroundStyle(WatchTheme.mint)
                        }.font(.system(size: compact ? 8 : 10, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                        GeometryReader { geometry in
                            Capsule().fill(.white.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(LinearGradient(colors: [WatchTheme.mint, Color(red: 0.22, green: 0.76, blue: 0.73)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geometry.size.width * WatchPresentation.progress(for: course, at: date))
                                }
                        }.frame(height: compact ? 4 : 5).accessibilityHidden(true)
                    }
                } else {
                    Label(WatchPresentation.upcomingText(for: course, at: date), systemImage: "hourglass")
                        .font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(WatchTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if status.simultaneous.count > 1 {
                    Label("同时另有 \(status.simultaneous.count - 1) 门课", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(WatchTheme.amber)
                }
            }
        }
        .padding(compact ? 10 : 12).frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.36, blue: 0.36), Color(red: 0.055, green: 0.20, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(dimmed ? 0.05 : 0.12), lineWidth: 0.7)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityHint("点按查看完整课程信息")
    }
}
struct WatchCourseTile: View {
    let course: CourseOccurrence
    let date: Date
    private var current: Bool { course.start <= date && date < course.end }
    private var past: Bool { course.end <= date }
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(WatchTheme.accent(for: course)).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(course.timeRange).font(.system(.caption, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(WatchTheme.accent(for: course)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if current { Text("上课中").font(.system(size: 9, weight: .semibold)).foregroundStyle(WatchTheme.mint) }
                    else if past { Image(systemName: "checkmark").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)) }
                }
                Text(course.title).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).foregroundStyle(WatchTheme.cream.opacity(past ? 0.65 : 1))
                Text(course.displayLocation).font(.caption2).foregroundStyle(.white.opacity(0.52)).lineLimit(2)
            }
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.30)).padding(.top, 3)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(current ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(current ? WatchTheme.mint.opacity(0.35) : .clear, lineWidth: 0.7) }
        .accessibilityElement(children: .combine)
    }
}
