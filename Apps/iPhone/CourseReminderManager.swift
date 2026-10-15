import Foundation
import Combine
import UserNotifications
import BackgroundTasks
import ScheduleCore

@MainActor final class CourseReminderManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = CourseReminderManager()
    static let backgroundIdentifier = "dev.courselist.app.reminders"
    private static let testIdentifier = "course-reminder-test"
    @Published private(set) var preferences: ReminderPreferences
    @Published private(set) var permissionText = "尚未检查"
    @Published private(set) var pendingCount = 0
    @Published private(set) var requestingPermission = false
    @Published var message: String?
    @Published var pendingCourseID: String?
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var worker: Task<Void, Never>?
    private var generation = 0

    private override init() {
        preferences = ReminderPreferences(enabled: UserDefaults.standard.bool(forKey: "reminder.enabled"),
            leadMinutes: UserDefaults.standard.object(forKey: "reminder.minutes") as? Int ?? 10)
        super.init()
        center.delegate = self
        let action = UNNotificationAction(identifier: "VIEW_COURSE", title: "查看课程", options: .foreground)
        center.setNotificationCategories([UNNotificationCategory(identifier: "COURSE_REMINDER", actions: [action], intentIdentifiers: [])])
    }
    func setEnabled(_ enabled: Bool) async {
        guard !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            let allowed = enabled ? try await center.requestAuthorization(options: [.alert, .sound]) : false
            preferences.enabled = enabled && allowed
            if enabled && !allowed { message = "请在系统设置中允许课表通知，然后重新开启提醒。" }
            persist(); refresh()
        } catch { message = "通知设置失败：\(error.localizedDescription)" }
    }
    func setMinutes(_ minutes: Int) {
        guard ReminderPreferences.supportedMinutes.contains(minutes) else { return }
        preferences.leadMinutes = minutes; persist(); refresh()
    }
    private func persist() {
        defaults.set(preferences.enabled, forKey: "reminder.enabled")
        defaults.set(preferences.leadMinutes, forKey: "reminder.minutes")
    }
    /// Chain jobs so a stale in-flight add finishes before the newest queue replaces it.
    func refresh() {
        generation += 1
        let current = generation, previous = worker
        worker = Task { @MainActor in
            await previous?.value
            guard current == self.generation, !Task.isCancelled else { return }
            await self.rebuild(generation: current)
        }
    }
    func refreshAndWait() async {
        refresh()
        await worker?.value
    }
    private func rebuild(generation current: Int) async {
        let settings = await center.notificationSettings()
        guard current == generation, !Task.isCancelled else { return }
        switch settings.authorizationStatus {
        case .authorized: permissionText = "已允许"
        case .denied: permissionText = "已关闭"
        case .notDetermined: permissionText = "尚未授权"
        case .provisional: permissionText = "静默通知"
        case .ephemeral: permissionText = "临时授权"
        @unknown default: permissionText = "未知状态"
        }
        let existing = await center.pendingNotificationRequests()
        guard current == generation, !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: existing.filter {
            $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) || $0.identifier == Self.testIdentifier
        }.map(\.identifier))
        pendingCount = 0
        guard preferences.enabled, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
            return
        }
        do {
            let snapshot = try PlatformStore.make().load()
            let plan = ReminderPlanner.plan(snapshot: snapshot, preferences: preferences, now: Date())
            for reminder in plan {
                guard current == generation, !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = reminder.title; content.body = reminder.body; content.sound = .default
                content.categoryIdentifier = "COURSE_REMINDER"
                content.threadIdentifier = "course-reminders"
                content.userInfo = ["courseID": reminder.courseID]
                var components = SchoolClock.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
                components.calendar = SchoolClock.calendar; components.timeZone = SchoolClock.calendar.timeZone
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                pendingCount += 1
            }
            scheduleBackgroundRefresh(hasCourses: !plan.isEmpty)
        } catch { message = "课前提醒安排失败：\(error.localizedDescription)" }
    }
    private func scheduleBackgroundRefresh(hasCourses: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
        guard hasCourses else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        // Background refresh is opportunistic; reopening/importing also replenishes the queue.
        try? BGTaskScheduler.shared.submit(request)
    }
    func sendTest() async {
        await worker?.value
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            message = "请先开启课前提醒并允许通知。"; return
        }
        do {
            let content = UNMutableNotificationContent()
            content.title = "课前提醒测试"; content.body = "课程开始前会收到这样的横幅，包含课程名称、时间和地点。"
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: Self.testIdentifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
            message = "测试提醒已安排，将在 10 秒后显示。"
        } catch { message = error.localizedDescription }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        // Don't remove a pending test request in response to the test banner.
        if notification.request.identifier.hasPrefix(ReminderPlanner.identifierPrefix) {
            Task { @MainActor in self.refresh() }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier != UNNotificationDismissActionIdentifier,
           let id = response.notification.request.content.userInfo["courseID"] as? String {
            Task { @MainActor in self.pendingCourseID = id; self.refresh() }
        }
        completionHandler()
    }
}
