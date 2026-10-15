import SwiftUI
import ScheduleCore

struct ManualCourseDay: Identifiable {
    let date: Date
    var id: Date { date }
}

struct ManualCourseView: View {
    @EnvironmentObject var model: ScheduleModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingText: Bool
    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var weekly = false
    @State private var repeatUntil: Date
    @State private var firstMonday: Date
    @State private var lastDay: Date
    @State private var error: String?
    @State private var confirmation: String?
    init(date: Date = Date()) {
        let cal = SchoolClock.calendar, day = cal.startOfDay(for: date)
        let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        _date = State(initialValue: day); _startTime = State(initialValue: start)
        _endTime = State(initialValue: start.addingTimeInterval(100 * 60))
        _repeatUntil = State(initialValue: cal.date(byAdding: .weekOfYear, value: 12, to: day)!)
        _firstMonday = State(initialValue: SchoolClock.monday(containing: day))
        _lastDay = State(initialValue: cal.date(byAdding: .day, value: 139, to: SchoolClock.monday(containing: day))!)
    }
    private var existing: ScheduleSnapshot? { model.snapshot?.isDemo == true ? nil : model.snapshot }
    private var semester: Semester {
        existing?.semester ?? Semester(name: "我的课表", firstMonday: SchoolClock.monday(containing: firstMonday),
            end: SchoolClock.calendar.date(byAdding: .day, value: 1, to: SchoolClock.calendar.startOfDay(for: lastDay))!)
    }
    private func time(on day: Date, using value: Date) -> Date {
        let cal = SchoolClock.calendar
        return cal.date(bySettingHour: cal.component(.hour, from: value), minute: cal.component(.minute, from: value), second: 0, of: day)!
    }
    private var draft: ManualCourseDraft {
        ManualCourseDraft(title: title, location: location, start: time(on: date, using: startTime),
                          end: time(on: date, using: endTime), notes: notes, weeklyThrough: weekly ? repeatUntil : nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称（必填）", text: $title).focused($editingText).accessibilityIdentifier("manual.title")
                    TextField("上课地点（选填）", text: $location).focused($editingText).accessibilityIdentifier("manual.location")
                    TextField("备注（选填）", text: $notes, axis: .vertical).lineLimit(2...4).focused($editingText).accessibilityIdentifier("manual.notes")
                }
                Section("上课时间 · 北京时间") {
                    DatePicker("上课日期", selection: $date, displayedComponents: .date).accessibilityIdentifier("manual.date")
                    DatePicker("上课时间", selection: $startTime, displayedComponents: .hourAndMinute).accessibilityIdentifier("manual.start")
                    DatePicker("下课时间", selection: $endTime, displayedComponents: .hourAndMinute).accessibilityIdentifier("manual.end")
                    Toggle("每周重复", isOn: $weekly).accessibilityIdentifier("manual.weekly")
                    if weekly {
                        DatePicker("重复至（含当天）", selection: $repeatUntil, displayedComponents: .date).accessibilityIdentifier("manual.until")
                        Text("从首次上课日起，每周同一星期、同一时间上课。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let count = try? draft.occurrences().count {
                        Text("将添加 \(count) 次课程").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("所属学期") {
                    if let existing {
                        Text(existing.semester.name)
                        Text(SchoolClock.format(existing.semester.firstMonday, "yyyy/M/d") + " – " +
                             SchoolClock.format(existing.semester.end.addingTimeInterval(-1), "yyyy/M/d"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("新增课程须在当前学期内。更新学校或 ICS 课表会保留手动课程。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        DatePicker("第一周周一", selection: $firstMonday, displayedComponents: .date)
                        DatePicker("学期最后一天", selection: $lastDay, displayedComponents: .date)
                        Text("首周会按所选日期归到周一，可先创建课表再导入学校课程。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.snapshot?.isDemo == true {
                        Text("当前为演示课表。保存时将创建个人课表并移除演示课程，操作前会再次确认。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("保存后自动更新课表与锁屏组件，并发送到手表；已开启的课前提醒会重新安排。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("添加课程").navigationBarTitleDisplayMode(.inline)
            .environment(\.calendar, SchoolClock.calendar).environment(\.timeZone, SchoolClock.calendar.timeZone)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成输入") { editingText = false } }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { prepareSave() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("manual.save")
                }
            }
            .onAppear {
                if let existing { repeatUntil = min(repeatUntil, existing.semester.end.addingTimeInterval(-1)) }
            }
            .alert("请检查课程信息", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("确定", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .confirmationDialog("确认添加课程？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                Button("确认添加") { save() }
            } message: { Text(confirmation ?? "") }
        }
    }
    private func prepareSave() {
        do {
            _ = try ManualCourseEditor.adding(draft, to: existing, semester: semester, origin: "preview", revision: 1)
            let conflicts = try ManualCourseEditor.conflictCount(for: draft, in: existing)
            var messages: [String] = []
            if model.snapshot?.isDemo == true { messages.append("将移除演示课程，创建个人课表。") }
            if conflicts > 0 { messages.append("与已有 \(conflicts) 次课程时间重叠，仍要添加吗？") }
            if messages.isEmpty { save() } else { confirmation = messages.joined(separator: "\n") }
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        do { try model.addManualCourse(draft, semester: semester); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
