import SwiftUI
import ScheduleCore

@main struct CourseListWatchApp: App {
    @StateObject private var model = ScheduleModel()
    var body: some Scene { WindowGroup { WatchRootView().environmentObject(model) } }
}
struct WatchRootView: View {
    @EnvironmentObject var model: ScheduleModel
    @Environment(\.scenePhase) private var phase
    @State private var selectedCourse: CourseOccurrence?
    private var preview: WatchPreview? { WatchPreview.active }
    private var snapshot: ScheduleSnapshot? { if let preview { return preview.snapshot }; return model.snapshot }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WatchBackdrop()
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    let date = preview?.date ?? context.date
                    let status = ScheduleEngine.status(in: snapshot, at: date)
                    let today = ScheduleEngine.courses(in: snapshot, on: date)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text(SchoolClock.format(date, "M月d日 EEE")).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.68))
                                Spacer(minLength: 0)
                                if let snapshot { Text("第 \(snapshot.semester.week(at: date)) 周").font(.system(size: 10, weight: .medium)).foregroundStyle(WatchTheme.mint.opacity(0.8)) }
                            }.padding(.horizontal, 9).accessibilityIdentifier("watch.date")
                            if let course = status.course {
                                Button { selectedCourse = course } label: {
                                    WatchCourseHero(status: status, snapshot: snapshot, date: date, minimumHeight: max(geometry.size.height - 70, geometry.size.width < 195 ? 130 : 174), compact: geometry.size.width < 195)
                                }.buttonStyle(.plain).accessibilityIdentifier("watch.hero")
                            } else {
                                WatchEmptyHero(phase: status.phase, isDemo: snapshot?.isDemo == true, minimumHeight: max(geometry.size.height - 70, geometry.size.width < 195 ? 130 : 174), compact: geometry.size.width < 195)
                            }
                            if status.stale {
                                Label("课表已超过 7 天未更新", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                                    .font(.caption2).foregroundStyle(WatchTheme.amber).padding(.horizontal, 7)
                            }
                            if status.phase == .current, let next = status.next {
                                Button { selectedCourse = next } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.turn.down.right").foregroundStyle(WatchTheme.amber)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("下一课 · \(SchoolClock.format(next.start, SchoolClock.calendar.isDate(next.start, inSameDayAs: date) ? "HH:mm" : "M/d HH:mm"))")
                                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                                            Text(next.title).font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(WatchTheme.cream).lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(WatchTheme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
                                }.buttonStyle(.plain).accessibilityIdentifier("watch.next")
                            }
                            HStack {
                                Text("今日安排").font(.system(.subheadline, design: .rounded, weight: .bold))
                                Spacer()
                                Text("\(today.count) 节").font(.system(.caption2, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                            }.foregroundStyle(WatchTheme.cream).padding(.horizontal, 7).padding(.top, 5)
                            if today.isEmpty {
                                Label("今天没有课程，享受空闲吧", systemImage: "cup.and.saucer")
                                    .font(.caption).foregroundStyle(.white.opacity(0.6)).padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 17))
                            }
                            ForEach(today) { course in
                                Button { selectedCourse = course } label: { WatchCourseTile(course: course, date: date) }
                                    .buttonStyle(.plain).accessibilityIdentifier("watch.course.\(course.id)")
                            }
                            WatchSyncPanel(snapshot: snapshot, message: model.syncMessage, preview: preview != nil) { model.synchronize() }
                        }
                        .padding(.horizontal, 7).padding(.top, 29).padding(.bottom, 18)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden).contentMargins(.horizontal, 0, for: .scrollContent).contentMargins(.top, 0, for: .scrollContent)
                }
            }
        }
        .ignoresSafeArea(.container, edges: [.horizontal, .top])
        .tint(WatchTheme.mint).environment(\.calendar, SchoolClock.calendar).environment(\.timeZone, SchoolClock.calendar.timeZone)
        .sheet(item: $selectedCourse) { WatchCourseDetailView(course: $0, isDemo: snapshot?.isDemo == true) }
        .alert("课表提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("确定") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onOpenURL { url in
            guard url.scheme == "courselist", url.host == "course",
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value else { return }
            selectedCourse = snapshot?.courses.first { $0.id == id }
        }
        .onChange(of: phase) { _, value in if value == .active { model.reload() } }
    }
}
private struct WatchEmptyHero: View {
    let phase: CoursePhase
    let isDemo: Bool
    let minimumHeight: CGFloat
    let compact: Bool
    private var title: String { switch phase { case .needsImport: "让课表随身而行"; case .expired: "开启新的学期"; default: "留点时间给自己" } }
    private var subtitle: String { switch phase { case .needsImport: "在 iPhone 添加或导入课程\n然后同步到这只手表"; case .expired: "本学期已结束\n请在 iPhone 更新课表"; default: "暂无后续课程\n休息一下，也很重要" } }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 13) {
            HStack { Text("COURSE / 课表").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(WatchTheme.mint); Spacer(minLength: 0); if isDemo { Text("演示").font(.caption2).foregroundStyle(WatchTheme.amber) } }
            Image(systemName: phase == .expired ? "calendar.badge.clock" : phase == .needsImport ? "calendar.badge.plus" : "leaf.fill")
                .font(.system(size: compact ? 26 : 30, weight: .light)).foregroundStyle(WatchTheme.mint).padding(.vertical, 3)
            Text(title).font(.system(size: compact ? 17 : 20, weight: .bold, design: .rounded)).foregroundStyle(WatchTheme.cream).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: compact ? 11 : 13)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(compact ? 12 : 14).frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(red: 0.10, green: 0.32, blue: 0.33), Color(red: 0.05, green: 0.18, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.10), lineWidth: 0.7) }
            .accessibilityElement(children: .combine).accessibilityIdentifier("watch.empty")
    }
}
private struct WatchSyncPanel: View {
    let snapshot: ScheduleSnapshot?
    let message: String
    let preview: Bool
    let synchronize: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: synchronize) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("同步课表").fontWeight(.semibold)
                }.font(.caption).foregroundStyle(WatchTheme.mint).frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(WatchTheme.mint.opacity(0.10), in: Capsule())
                    .overlay { Capsule().strokeBorder(WatchTheme.mint.opacity(0.18), lineWidth: 0.7) }
            }.buttonStyle(.plain).accessibilityIdentifier("watch.sync")
            Text(preview ? "演示预览 · 不写入真实课表" : message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.56)).frame(maxWidth: .infinity)
            if let snapshot { Text("更新于 \(SchoolClock.format(snapshot.fetchedAt, "M/d HH:mm")) · 北京时间").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity) }
        }.padding(.top, 7)
    }
}
struct WatchCourseDetailView: View {
    let course: CourseOccurrence
    let isDemo: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(course.title).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(WatchTheme.cream).fixedSize(horizontal: false, vertical: true)
                    if isDemo { WatchPhasePill(title: "演示课程", color: WatchTheme.amber) }
                    VStack(alignment: .leading, spacing: 12) {
                        Label(SchoolClock.format(course.start, "M月d日 EEEE"), systemImage: "calendar")
                        Label(course.timeRange, systemImage: "clock").monospacedDigit()
                        Label(course.location.isEmpty ? "地点待定" : course.location, systemImage: "mappin.and.ellipse")
                    }.font(.caption).foregroundStyle(WatchTheme.mint).fixedSize(horizontal: false, vertical: true)
                    if !course.notes.isEmpty { Text(course.notes).font(.caption).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true) }
                }.padding(.horizontal, 12).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
            }.background { WatchBackdrop() }.navigationTitle("课程详情")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }.tint(WatchTheme.mint)
    }
}
