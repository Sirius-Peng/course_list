import SwiftUI
import ScheduleCore
import BackgroundTasks

@main struct CourseListApp: App {
    @StateObject private var model = ScheduleModel()
    @StateObject private var reminders = CourseReminderManager.shared
    @StateObject private var subscriptions = ICSSubscriptionManager.shared
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).environmentObject(reminders).environmentObject(subscriptions) }
            .backgroundTask(.appRefresh(CourseReminderManager.backgroundIdentifier)) {
                await CourseReminderManager.shared.refreshAndWait()
            }
            .backgroundTask(.appRefresh(ICSSubscriptionManager.backgroundIdentifier)) {
                await ICSSubscriptionManager.shared.refreshIfNeeded(using: model)
            }
    }
}
struct RootView: View {
    @EnvironmentObject var subscriptions: ICSSubscriptionManager
    @EnvironmentObject var model: ScheduleModel
    @EnvironmentObject var reminders: CourseReminderManager
    @Environment(\.scenePhase) private var phase
    @State private var selection = 0
    @State private var selectedCourse: CourseOccurrence?
    @State private var schoolLogin = false
    var body: some View {
        TabView(selection: $selection) {
            Tab("今日", systemImage: "sun.max", value: 0) { TodayView(selectedCourse: $selectedCourse) }
            Tab("课表", systemImage: "calendar", value: 1) { WeekScheduleView(selectedCourse: $selectedCourse) }
            Tab("设置", systemImage: "slider.horizontal.3", value: 2) { SettingsView() }
        }
        .tint(Color(red: 0.18, green: 0.45, blue: 0.43))
        .environment(\.calendar, SchoolClock.calendar)
        .environment(\.timeZone, SchoolClock.calendar.timeZone)
        .sheet(item: $selectedCourse) { CourseDetailView(course: $0) }
        .sheet(isPresented: $schoolLogin) { ImportView(source: 1) }
        .onOpenURL { url in
            guard url.scheme == "courselist" else { return }
            selection = 0
            if url.host == "login" { selectedCourse = nil; schoolLogin = true; return }
            if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
                selectedCourse = model.snapshot?.courses.first { $0.id == id }
            }
        }
        .task { reminders.refresh(); openReminderCourse(); await subscriptions.refreshIfNeeded(using: model) }
        .onChange(of: reminders.pendingCourseID) { _, _ in openReminderCourse() }
        .onChange(of: phase) { _, value in if value == .active { model.reload(); reminders.refresh(); Task { await subscriptions.refreshIfNeeded(using: model) } } }
        .alert("课表提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("确定") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private func openReminderCourse() {
        guard let id = reminders.pendingCourseID else { return }
        selection = 0; selectedCourse = model.snapshot?.courses.first { $0.id == id }
        reminders.pendingCourseID = nil
    }
}
struct TodayView: View {
    @EnvironmentObject var model: ScheduleModel
    @Binding var selectedCourse: CourseOccurrence?
    @State private var importing = false
    @State private var adding = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(SchoolClock.format(context.date, "M月d日 EEEE")).font(.largeTitle.bold())
                                Text(subtitle(at: context.date)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "leaf").font(.title).foregroundStyle(.tint)
                        }
                        CourseStatusCard(snapshot: model.snapshot, date: context.date)
                            .accessibilityIdentifier("course.status")
                        if model.snapshot == nil || model.snapshot?.isCleared == true {
                            VStack(spacing: 12) {
                                Button("导入我的课表", systemImage: "square.and.arrow.down") { importing = true }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .accessibilityIdentifier("schedule.import")
                                Button("手动添加课程", systemImage: "calendar.badge.plus") { adding = true }
                                    .accessibilityIdentifier("schedule.emptyManualAdd")
                                Button("先体验演示课表") { model.loadDemo() }
                                    .accessibilityIdentifier("schedule.demo")
                                Text("演示数据会明确标记，随时可替换为真实课程。")
                                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical)
                        }
                        HStack {
                            Text("今日安排").font(.title3.bold())
                            Spacer()
                            Text("北京时间").font(.caption).foregroundStyle(.secondary)
                        }
                        let courses = ScheduleEngine.courses(in: model.snapshot, on: context.date)
                        if courses.isEmpty {
                            ContentUnavailableView("今天没有课程", systemImage: "cup.and.saucer", description: Text("留一点时间，做喜欢的事。"))
                        }
                        ForEach(courses) { course in
                            Button { selectedCourse = course } label: {
                                CourseRow(course: course).foregroundStyle(.primary).padding(14)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                        if let snapshot = model.snapshot {
                            Text("最近更新 \(SchoolClock.format(snapshot.fetchedAt, "M/d HH:mm")) · \(snapshot.courses.count) 次课程")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(20)
                }.background(Color(.systemGroupedBackground))
            }
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
                Button("添加课程", systemImage: "calendar.badge.plus") { adding = true }.accessibilityIdentifier("schedule.manualAdd")
                Button("导入", systemImage: "square.and.arrow.down") { importing = true }
            } }
            .sheet(isPresented: $importing) { ImportView() }
            .sheet(isPresented: $adding) { ManualCourseView() }
        }
    }
    private func subtitle(at date: Date) -> String {
        guard let s = model.snapshot, !s.isCleared else { return "课程 · 时间 · 地点，一眼就知道" }
        return "\(s.semester.name) · 第 \(s.semester.week(at: date)) 周\(s.isDemo ? " · 演示" : "")"
    }
}
struct WeekScheduleView: View {
    @EnvironmentObject var model: ScheduleModel
    @Binding var selectedCourse: CourseOccurrence?
    @State private var offset = 0
    @State private var addingDay: ManualCourseDay?
    private var monday: Date { SchoolClock.calendar.date(byAdding: .weekOfYear, value: offset, to: SchoolClock.monday(containing: Date()))! }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Button("上一周", systemImage: "chevron.left") { offset -= 1 }.labelStyle(.iconOnly)
                        Spacer()
                        VStack(spacing: 4) {
                            Text(model.snapshot.map { "第 \($0.semester.week(at: monday)) 周" } ?? "本周").font(.headline)
                            Text(SchoolClock.format(monday, "M月d日") + " – " + SchoolClock.format(SchoolClock.calendar.date(byAdding: .day, value: 6, to: monday)!, "M月d日"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("下一周", systemImage: "chevron.right") { offset += 1 }.labelStyle(.iconOnly)
                    }.padding(.horizontal)
                    if model.snapshot == nil || model.snapshot?.isCleared == true {
                        ContentUnavailableView("还没有课表", systemImage: "calendar.badge.plus", description: Text("点击右上角添加课程，也可在今日或设置页导入。"))
                    } else {
                        // Use a readable horizontal grid instead of squeezing seven columns on a phone.
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(0..<7, id: \.self) { day in
                                    let date = SchoolClock.calendar.date(byAdding: .day, value: day, to: monday)!
                                    let courses = ScheduleEngine.courses(in: model.snapshot, on: date)
                                    VStack(spacing: 10) {
                                        VStack(spacing: 4) {
                                            Text(SchoolClock.format(date, "EEE")).font(.caption)
                                            Text(SchoolClock.format(date, "d")).font(.title3.bold())
                                        }
                                        .foregroundStyle(SchoolClock.calendar.isDateInToday(date) ? Color.accentColor : Color.primary)
                                        .frame(maxWidth: .infinity).padding(10)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        Button("添加当天课程", systemImage: "plus.circle") { addingDay = ManualCourseDay(date: date) }
                                            .labelStyle(.iconOnly).accessibilityIdentifier("manual.day.\(day)")
                                        ForEach(courses) { course in
                                            Button { selectedCourse = course } label: {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(course.title).font(.subheadline.bold()).lineLimit(3)
                                                    Text(course.timeRange).font(.caption2).monospacedDigit()
                                                    Text(course.displayLocation).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                                .foregroundStyle(.primary)
                                                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                            }.buttonStyle(.plain)
                                        }
                                        if courses.isEmpty { Text("无课").font(.caption).foregroundStyle(.tertiary).padding(.top, 20) }
                                    }.frame(width: 112)
                                }
                            }.padding(.horizontal)
                        }
                        Text("左右滑动查看全周 · 点击课程查看详情").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical)
            }
            .navigationTitle("课程表")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("回到本周") { offset = 0 } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加课程", systemImage: "plus") {
                        addingDay = ManualCourseDay(date: SchoolClock.calendar.isDate(Date(), equalTo: monday, toGranularity: .weekOfYear) ? Date() : monday)
                    }.accessibilityIdentifier("week.manualAdd")
                }
            }
            .sheet(item: $addingDay) { ManualCourseView(date: $0.date) }
        }
    }
}
struct CourseDetailView: View {
    @EnvironmentObject var model: ScheduleModel
    @State private var confirmDelete = false
    let course: CourseOccurrence
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text(course.title).font(.title2.bold()) }
                Section("课程信息") {
                    Label(SchoolClock.format(course.start, "yyyy年M月d日 EEEE"), systemImage: "calendar")
                    Label(course.timeRange + "（北京时间）", systemImage: "clock")
                    Label(course.location.isEmpty ? "地点待定" : course.location, systemImage: "mappin.and.ellipse")
                }
                if !course.notes.isEmpty { Section("备注") { Text(course.notes) } }
                if (model.snapshot?.manualCourseIDs ?? []).contains(course.id) {
                    Section {
                        Label("手动添加", systemImage: "pencil")
                        Button("删除本次课程", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("manual.delete")
                    } footer: { Text("仅删除这一次上课，不影响其他重复课程；同步更新手表与提醒。") }
                }
            }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() } }
                .confirmationDialog("删除本次手动课程？", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("删除本次课程", role: .destructive) {
                        do { try model.removeManualCourse(course.id); dismiss() }
                        catch { model.errorMessage = error.localizedDescription }
                    }
                }
        }
    }
}
struct SettingsView: View {
    @State private var subscribing = false
    @EnvironmentObject var model: ScheduleModel
    @EnvironmentObject var reminders: CourseReminderManager
    @State private var importing = false
    @State private var adding = false
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            Form {
                Section("课表数据") {
                    Button("导入 / 更新课表", systemImage: "square.and.arrow.down") { importing = true }
                    Button("手动添加课程", systemImage: "calendar.badge.plus") { adding = true }.accessibilityIdentifier("settings.manualAdd")
                    Button("加载演示课表", systemImage: "sparkles") { model.loadDemo() }
                    if let snapshot = model.snapshot, !snapshot.isCleared {
                        LabeledContent("当前学期", value: snapshot.semester.name)
                        LabeledContent("课程次数", value: "\(snapshot.courses.count)")
                        LabeledContent("上次更新", value: SchoolClock.format(snapshot.fetchedAt, "M/d HH:mm"))
                        Button("清空课表", role: .destructive) { confirmClear = true }
                    }
                }
                Section("课前提醒") {
                    Toggle("开启课前弹窗提醒", isOn: Binding(get: { reminders.preferences.enabled }, set: { value in
                        Task { await reminders.setEnabled(value) }
                    })).disabled(reminders.requestingPermission).accessibilityIdentifier("reminder.enabled")
                    Picker("提前时间", selection: Binding(get: { reminders.preferences.leadMinutes }, set: { reminders.setMinutes($0) })) {
                        ForEach(ReminderPreferences.supportedMinutes, id: \.self) { Text("提前 \($0) 分钟").tag($0) }
                    }.accessibilityIdentifier("reminder.minutes")
                    LabeledContent("通知权限", value: reminders.permissionText)
                    LabeledContent("已安排", value: "\(reminders.pendingCount) 次提醒")
                    Button("发送 10 秒测试提醒", systemImage: "bell.badge") { Task { await reminders.sendTest() } }
                        .disabled(!reminders.preferences.enabled).accessibilityIdentifier("reminder.test")
                    if reminders.permissionText == "已关闭" {
                        Link("打开通知设置", destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                    }
                    Text("使用系统通知：前台显示横幅，锁屏时也可提醒。手机负责发送，手表按系统设置镜像，避免重复提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("每次安排最近 60 次未来提醒，打开 App、更新课表或后台刷新时会自动补排。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = reminders.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Apple Watch") {
                    LabeledContent("同步状态", value: model.syncMessage)
                    Button("重新同步到手表", systemImage: "arrow.triangle.2.circlepath") { model.synchronize() }
                    Text("手表保存本地课表，断开手机后仍可查看；传输后会等待手表接收确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("iOS 26 锁屏小组件") {
                    Label("矩形：课程名、时间和地点", systemImage: "rectangle")
                    Label("圆形：上课进度 / 下一课时间", systemImage: "circle")
                    Label("单行：简短课程信息", systemImage: "text.alignleft")
                    Text("长按锁屏 → 自定 → 锁定屏幕 → 添加小组件 → 选择「课表」。矩形样式占用两个小槽位。")
                    Text("组件依据课表时间线自动切换；实际刷新时机由系统调度。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Watch 表盘") {
                    Text("长按表盘 → 编辑 → 复杂功能 → 选择「课表」。可用样式取决于表盘槽位。")
                }
                ICSSubscriptionSection { subscribing = true }
                Section { Text("学校时间固定为北京时间。密码和验证码不保存；首版每次学校拉取重新认证。")
                    .font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("设置")
                .sheet(isPresented: $importing) { ImportView() }
                .sheet(isPresented: $adding) { ManualCourseView() }
                .sheet(isPresented: $subscribing) { ImportView(source: 2) }
                .confirmationDialog("清空手机课表并通知手表？", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("清空课表", role: .destructive) { model.clear() }
                }
        }
    }
}
