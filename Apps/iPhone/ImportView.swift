import SwiftUI
import UniformTypeIdentifiers
import ScheduleCore

struct ImportView: View {
    @EnvironmentObject var model: ScheduleModel
    @EnvironmentObject var subscriptions: ICSSubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("loginServer") private var server = "https://login.bit101.flwfdd.xyz"
    @State private var mode: Int
    @State private var feedAddress = ""
    @State private var feedPreview: ICSFeedDownload?
    @State private var term = ""
    @State private var firstDay = Self.suggestedFirstMonday()
    @State private var lastDay = SchoolClock.calendar.date(byAdding: .day, value: 139, to: Self.suggestedFirstMonday())!
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challenge: AuthChallenge?
    @State private var client: BITLoginClient?
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var generation = UUID()
    @State private var status = ""
    @State private var error: String?
    @State private var filePicker = false
    @State private var courses: [CourseOccurrence]?
    init(source: Int = 0) { _mode = State(initialValue: source) }
    private var semester: Semester {
        Semester(name: term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我的学期" : term,
                 firstMonday: SchoolClock.monday(containing: firstDay), end: SchoolClock.calendar.date(byAdding: .day, value: 1, to: SchoolClock.calendar.startOfDay(for: lastDay))!)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("数据来源", selection: $mode) {
                        Text("ICS 文件").tag(0); Text("学校拉取").tag(1); Text("链接订阅").tag(2)
                    }.pickerStyle(.segmented).disabled(busy || challenge != nil)
                }
                Section("学期设置") {
                    TextField("学期代码，如 2026-2027-1", text: $term).textInputAutocapitalization(.never).autocorrectionDisabled()
                    DatePicker("第一周周一", selection: $firstDay, displayedComponents: .date)
                    DatePicker("学期最后一天", selection: $lastDay, displayedComponents: .date)
                    Text("首周日期为建议值，请按学校校历核对。导入会替换原导入课程，保留手动添加的课程。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if mode == 0 {
                    Section("选择课程表") {
                        Button("选择 .ics 文件", systemImage: "doc.badge.plus") { filePicker = true }
                        Text("支持 BIT101 导出的已展开课表，以及有明确结束范围的日 / 周重复规则。全天日历事件不作为课程。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if mode == 2 {
                    Section("ICS 链接订阅") {
                        TextField("HTTPS 或 webcal:// 日历链接", text: $feedAddress)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(busy).privacySensitive().accessibilityIdentifier("subscription.url")
                        Button("下载并预览", systemImage: "link.badge.plus") { downloadFeed() }
                            .disabled(busy || feedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("subscription.preview")
                        if busy {
                            ProgressView("正在下载订阅…")
                            Button("取消下载", role: .cancel) { cancelLogin() }
                        } else if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                        Text("支持与文件导入相同的 ICS 格式。使用日历文件的直接下载链接。webcal:// 会转换为 HTTPS；确认订阅后保存链接，支持手动刷新和约每 6 小时自动检查。后台时机由系统安排。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("链接可能含访问令牌，仅保存在本机钥匙串，不发送到手表。订阅更新会保留手动添加的课程。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("学校统一身份认证") {
                        TextField("HTTPS 登录服务地址", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(busy || challenge != nil).accessibilityIdentifier("auth.server")
                        Button("检查认证服务连接", systemImage: "network") { checkService() }
                            .disabled(busy || challenge != nil).accessibilityIdentifier("auth.health")
                        TextField("学号", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textContentType(.username).disabled(busy || challenge != nil).accessibilityIdentifier("auth.username")
                        SecureField("统一认证密码", text: $password).textContentType(.password)
                            .disabled(busy || challenge != nil).accessibilityIdentifier("auth.password")
                        Text("此地址是 BIT-Login 认证服务，不是学校门户网址；学校账号信息会提交到所选服务。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let challenge, challenge.requiresInput {
                            if challenge.status == "waiting_captcha", let uri = challenge.captchaImage,
                               let data = Data(base64Encoded: String(uri.split(separator: ",", maxSplits: 1).last ?? "")), let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 100)
                            }
                            Text(challenge.status == "waiting_sms" ? "请输入发送至 \(challenge.maskedPhone ?? "绑定手机") 的验证码" : "请输入图形验证码")
                            TextField("验证码", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("提交验证码") { submitCode() }.disabled(busy || code.isEmpty)
                        }
                        if challenge == nil {
                            Button("认证并获取课表", systemImage: "arrow.down.circle") { startLogin() }
                                .disabled(busy || username.isEmpty || password.isEmpty).accessibilityIdentifier("auth.login")
                        } else {
                            Button("取消 / 重新认证", role: .destructive) { cancelLogin() }
                        }
                        if busy { ProgressView(status) }
                        else if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let courses {
                    Section("导入预览") {
                        LabeledContent("课程次数", value: "\(courses.count)")
                        if let first = courses.first, let last = courses.last {
                            Text("\(SchoolClock.format(first.start, "yyyy/M/d")) 至 \(SchoolClock.format(last.end, "yyyy/M/d"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(courses.prefix(3))) { CourseRow(course: $0) }
                        if courses.isEmpty { Text("文件没有有时段的课程；确认后仅保留已有手动课程。") }
                        Button(mode == 2 ? "确认订阅并同步" : "确认替换并同步", systemImage: "checkmark.circle") {
                            do {
                                if mode == 2 {
                                    guard let feedPreview else { throw ICSFeedError.unexpectedNotModified }
                                    try subscriptions.subscribe(feedPreview, semester: semester, using: model)
                                } else { try model.importCourses(courses, semester: semester) }
                                dismiss()
                            }
                            catch { self.error = error.localizedDescription }
                        }.disabled(busy).accessibilityIdentifier("schedule.confirmImport")
                    }
                }
                if subscriptions.subscription != nil, mode != 2 {
                    Section { Text("确认导入本地文件或学校课表后，将停止当前链接订阅；手动课程仍会保留。")
                        .font(.caption).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("import.error") } }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("导入课表").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data]) { result in
                courses = nil
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 4_000_000 else { throw ScheduleError.invalid("ICS 文件超过 4 MB") }
                    try stage(String(contentsOf: url, encoding: .utf8))
                } catch { self.error = error.localizedDescription }
            }
            .onDisappear { cancelLogin() }
            .onChange(of: mode) { _, _ in cancelLogin(); courses = nil; feedPreview = nil; status = ""; error = nil }
            .onChange(of: feedAddress) { _, _ in
                if mode == 2 { cancelLogin(); courses = nil; feedPreview = nil; status = ""; error = nil }
            }
            .onAppear {
                if mode == 2, let record = subscriptions.subscription { feedAddress = record.url.absoluteString }
                if let snapshot = model.snapshot, !snapshot.isDemo, !snapshot.isCleared {
                    term = snapshot.semester.name; firstDay = snapshot.semester.firstMonday
                    lastDay = SchoolClock.calendar.date(byAdding: .day, value: -1, to: snapshot.semester.end)!
                }
            }
        }
        .environment(\.calendar, SchoolClock.calendar).environment(\.timeZone, SchoolClock.calendar.timeZone)
    }
    private func stage(_ text: String) throws {
        let parsed = try ICSParser().parse(text)
        courses = parsed; error = nil; status = "已取得课表，请核对日期后确认导入"
    }
    private func downloadFeed() {
        cancelLogin(); error = nil; courses = nil; feedPreview = nil; status = "正在下载订阅…"; busy = true
        let runID = UUID(); generation = runID
        task = Task { @MainActor in
            do {
                let result = try await subscriptions.client.fetch(feedAddress)
                try Task.checkCancellation()
                guard generation == runID else { return }
                guard let parsed = result.courses else { throw ICSFeedError.unexpectedNotModified }
                feedPreview = result; courses = parsed; status = "已下载，请核对课程和学期后确认订阅"
            } catch { if !Task.isCancelled && generation == runID { self.error = error.localizedDescription } }
            if generation == runID { busy = false }
        }
    }
    private func checkService() {
        error = nil; busy = true; status = "正在检查服务连接…"
        let runID = UUID(); generation = runID
        task = Task { @MainActor in
            do {
                guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ScheduleError.invalid("服务地址格式无效") }
                let message = try await BITLoginClient(baseURL: url).healthCheck()
                if generation == runID { status = message }
            } catch { if !Task.isCancelled && generation == runID { self.error = error.localizedDescription } }
            if generation == runID { busy = false }
        }
    }
    private func startLogin() {
        error = nil; courses = nil; busy = true; status = "正在认证…"
        let submittedPassword = password; password = ""
        let runID = UUID(); generation = runID
        task = Task { @MainActor in
            do {
                guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ScheduleError.invalid("服务地址格式无效") }
                let service = try BITLoginClient(baseURL: url); client = service
                let value = try await service.start(username: username, password: submittedPassword)
                try await settle(value, using: service)
            } catch { if !Task.isCancelled && generation == runID { self.error = error.localizedDescription } }
            if generation == runID { busy = false }
        }
    }
    private func submitCode() {
        guard let service = client, let challenge else { return }
        let submittedCode = code; code = ""; error = nil; busy = true; status = "正在验证…"
        let runID = UUID(); generation = runID
        task = Task { @MainActor in
            do {
                let result = try await service.submit(code: submittedCode, type: challenge.status == "waiting_sms" ? "sms" : "captcha")
                try await settle(result, using: service)
            } catch { if !Task.isCancelled && generation == runID { self.error = error.localizedDescription } }
            if generation == runID { busy = false }
        }
    }
    @MainActor private func settle(_ initial: AuthChallenge, using service: BITLoginClient) async throws {
        var value = initial
        while !value.requiresInput && !value.authenticated {
            try Task.checkCancellation()
            status = "等待学校认证…"
            try await Task.sleep(for: .milliseconds(800))
            value = try await service.poll()
        }
        try Task.checkCancellation()
        challenge = value
        if value.authenticated {
            status = "正在下载课表…"
            let text = try await service.downloadSchedule(term: term)
            try Task.checkCancellation()
            try stage(text)
        } else { status = "请完成验证码验证" }
    }
    private func cancelLogin() {
        generation = UUID(); task?.cancel(); task = nil
        let service = client; client = nil; challenge = nil; code = ""; password = ""; busy = false
        Task { await service?.cancel() }
    }
    private static func suggestedFirstMonday() -> Date {
        let cal = SchoolClock.calendar, now = Date(), year = cal.component(.year, from: now), month = cal.component(.month, from: now)
        let start = cal.date(from: DateComponents(year: month >= 8 ? year : year - (month == 1 ? 1 : 0), month: month >= 8 || month == 1 ? 9 : 2, day: 1))!
        let offset = (9 - cal.component(.weekday, from: start)) % 7
        return cal.date(byAdding: .day, value: offset, to: start)!
    }
}
