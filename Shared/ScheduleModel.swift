import Foundation
import Combine
import WidgetKit
import WatchConnectivity
import ScheduleCore

@MainActor final class ScheduleModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: ScheduleSnapshot?
    @Published var errorMessage: String?
    @Published private(set) var syncMessage = "尚未同步"
    private var pendingFile: Data?
    private let defaults = UserDefaults.standard
    private var origin: String {
        if let value = defaults.string(forKey: "origin") { return value }
        let value = UUID().uuidString; defaults.set(value, forKey: "origin"); return value
    }
    override init() {
        super.init()
        #if os(iOS) && DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            try? SecureSubscriptionStore().save(nil)
            UserDefaults.standard.removeObject(forKey: "reminder.enabled")
            UserDefaults.standard.removeObject(forKey: "reminder.minutes")
            if let store = try? PlatformStore.make() { try? FileManager.default.removeItem(at: store.fileURL) }
        }
        #endif
        reload()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func reload() {
        do { snapshot = try PlatformStore.make().load() }
        catch { errorMessage = error.localizedDescription }
    }
    private func nextRevision() -> Int64 {
        let previous = max(Int64(defaults.integer(forKey: "revision")), snapshot?.origin == origin ? snapshot?.revision ?? 0 : 0)
        let value = previous + 1; defaults.set(value, forKey: "revision"); return value
    }
    #if os(iOS)
    func importCourses(_ courses: [CourseOccurrence], semester: Semester, keepSubscription: Bool = false) throws {
        let value = try ManualCourseEditor.replacingImported(courses, semester: semester, current: snapshot, origin: origin, revision: nextRevision())
        if keepSubscription { try commit(value); sendLatest() }
        else { try ICSSubscriptionManager.shared.replacingSource { try commit(value); sendLatest() } }
    }
    func markSubscriptionChecked() throws {
        guard let snapshot, !snapshot.isCleared, !snapshot.isDemo else { throw ICSFeedError.unexpectedNotModified }
        try commit(ScheduleSnapshot(origin: origin, revision: nextRevision(), semester: snapshot.semester,
            courses: snapshot.courses, manualCourseIDs: snapshot.manualCourseIDs ?? [])); sendLatest()
    }
    func addManualCourse(_ draft: ManualCourseDraft, semester: Semester) throws {
        let current = snapshot?.isDemo == true ? nil : snapshot
        let value = try ManualCourseEditor.adding(draft, to: current, semester: semester, origin: origin, revision: nextRevision())
        try commit(value); sendLatest()
    }
    func removeManualCourse(_ id: String) throws {
        guard let snapshot else { return }
        let value = try ManualCourseEditor.removing(id, from: snapshot, origin: origin, revision: nextRevision())
        try commit(value); sendLatest()
    }
    func loadDemo() {
        do { try ICSSubscriptionManager.shared.replacingSource { try commit(DemoSchedule.make(origin: origin, revision: nextRevision())); sendLatest() } }
        catch { errorMessage = error.localizedDescription }
    }
    func clear() {
        guard let snapshot else { return }
        do {
            try ICSSubscriptionManager.shared.replacingSource {
                try commit(ScheduleSnapshot(origin: origin, revision: nextRevision(), semester: snapshot.semester, courses: [], isCleared: true))
                sendLatest()
            }
        } catch { errorMessage = error.localizedDescription }
    }
    #endif
    private func commit(_ value: ScheduleSnapshot) throws {
        try PlatformStore.make().save(value)
        snapshot = value
        WidgetCenter.shared.reloadTimelines(ofKind: "CourseStatus")
        #if os(iOS)
        CourseReminderManager.shared.refresh()
        #endif
    }
    func synchronize() {
        #if os(iOS)
        sendLatest()
        #else
        requestLatest()
        #endif
    }
    #if os(iOS)
    private func sendLatest() {
        guard let value = snapshot, WCSession.isSupported() else { syncMessage = "请先导入课表"; return }
        let session = WCSession.default
        guard session.activationState == .activated else { syncMessage = "正在连接手表"; return }
        guard session.isPaired, session.isWatchAppInstalled else { syncMessage = "请安装并打开手表 App"; return }
        do {
            let data = try value.encoded()
            var context: [String: Any] = ["origin": value.origin, "revision": value.revision, "hash": value.contentHash]
            if data.count < 48_000 { context["snapshot"] = data }
            try session.updateApplicationContext(context)
            if data.count >= 48_000 {
                let directory = try PlatformStore.make().directory.appendingPathComponent("Outgoing")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("\(value.revision)-\(UUID().uuidString).json")
                try data.write(to: url, options: .atomic)
                session.transferFile(url, metadata: ["schedule": true])
            }
            syncMessage = "已发送 · 等待手表确认"
            if session.isReachable, data.count < 48_000 {
                session.sendMessage(["snapshot": data], replyHandler: nil, errorHandler: { _ in })
            }
        } catch { syncMessage = "同步失败：\(error.localizedDescription)" }
    }
    #else
    private func requestLatest() {
        let session = WCSession.default
        guard session.activationState == .activated else { syncMessage = "正在连接手机"; return }
        do {
            try session.updateApplicationContext(["request": true])
            syncMessage = "已请求 · 等待手机"
            if session.isReachable { session.sendMessage(["request": true], replyHandler: nil, errorHandler: { _ in }) }
        } catch { syncMessage = "请求失败：\(error.localizedDescription)" }
    }
    private func receive(_ data: Data) {
        do {
            let candidate = try ScheduleSnapshot.decode(data)
            let head = WCSession.default.receivedApplicationContext
            guard let expectedOrigin = head["origin"] as? String,
                  let expectedRevision = head["revision"] as? Int64,
                  let expectedHash = head["hash"] as? String else { pendingFile = data; return }
            if candidate.origin == expectedOrigin && candidate.revision > expectedRevision { pendingFile = data; return }
            guard SyncPolicy.accepts(candidate, current: snapshot, expectedOrigin: expectedOrigin,
                                     expectedRevision: expectedRevision, expectedHash: expectedHash) else { return }
            try commit(candidate)
            pendingFile = nil
            syncMessage = "已接收 · \(SchoolClock.format(Date(), "HH:mm"))"
            WCSession.default.transferUserInfo(["ackOrigin": candidate.origin, "ackRevision": candidate.revision, "ackHash": candidate.contentHash])
        } catch { errorMessage = error.localizedDescription; syncMessage = "接收失败" }
    }
    #endif
    private func handle(_ message: [String: Any]) {
        #if os(iOS)
        if message["request"] as? Bool == true { sendLatest() }
        if let ack = message["ackRevision"] as? Int64, let value = snapshot,
           message["ackOrigin"] as? String == value.origin, ack == value.revision,
           message["ackHash"] as? String == value.contentHash { syncMessage = "手表已接收 · 版本 \(ack)" }
        #else
        if let data = message["snapshot"] as? Data { receive(data) }
        else if let pendingFile { receive(pendingFile) }
        #endif
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.syncMessage = error.localizedDescription; return }
            #if os(iOS)
            self.sendLatest()
            #else
            self.handle(session.receivedApplicationContext)
            self.requestLatest()
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.handle(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(userInfo) }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Read while WCSession's temporary URL is still valid.
        let data = try? Data(contentsOf: file.fileURL)
        Task { @MainActor in
            #if os(watchOS)
            if let data { self.receive(data) }
            #endif
        }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
        else { Task { @MainActor in self.syncMessage = "文件传输失败，请重试同步" } }
    }
    #endif
}
