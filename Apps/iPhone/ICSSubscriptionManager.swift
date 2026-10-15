import Foundation
import Combine
import BackgroundTasks
import ScheduleCore

@MainActor final class ICSSubscriptionManager: ObservableObject {
    static let shared = ICSSubscriptionManager()
    static let backgroundIdentifier = "dev.courselist.app.ics-refresh"
    @Published private(set) var subscription: ICSSubscription?
    @Published private(set) var isRefreshing = false
    @Published private(set) var message: String?
    private let store = SecureSubscriptionStore()
    let client: ICSFeedClient
    private var generation = UUID()
    private var refreshTask: Task<Void, Never>?
    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestICSFeed") {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureFeedProtocol.self]
            client = ICSFeedClient(session: URLSession(configuration: config))
        } else { client = ICSFeedClient() }
        #else
        client = ICSFeedClient()
        #endif
        do { subscription = try store.load() } catch { message = error.localizedDescription }
    }
    func subscribe(_ download: ICSFeedDownload, semester: Semester, using model: ScheduleModel) throws {
        guard let courses = download.courses else { throw ICSFeedError.unexpectedNotModified }
        _ = try ManualCourseEditor.replacingImported(courses, semester: semester, current: model.snapshot, origin: "preview", revision: 1)
        var next = try ICSSubscription(url: download.url, semester: semester)
        next.etag = download.etag; next.lastModified = download.lastModified
        next.lastAttemptAt = Date(); next.lastCheckedAt = next.lastAttemptAt; next.lastUpdatedAt = next.lastAttemptAt
        let previous = try store.load()
        try store.save(next); invalidate()
        do { try model.importCourses(courses, semester: semester, keepSubscription: true) }
        catch { try? store.save(previous); subscription = previous; schedule(); throw error }
        subscription = next; message = "已保存订阅，课程已更新"; schedule()
    }
    func stop() throws {
        try store.save(nil); invalidate(); subscription = nil
        message = "已停止订阅，当前课程已保留"; schedule()
    }
    /// A new file/school source or demo/clear explicitly replaces the subscription.
    func replacingSource(_ apply: () throws -> Void) throws {
        if subscription == nil { subscription = try store.load() }
        guard let old = subscription else { try apply(); return }
        try stop()
        do { try apply() }
        catch { try? store.save(old); subscription = old; schedule(); throw error }
    }
    func setAutomatic(_ enabled: Bool) throws {
        guard var record = subscription else { return }
        record.automatic = enabled; try store.save(record); invalidate(); subscription = record
        message = enabled ? "已开启自动更新" : "已关闭自动更新，可手动刷新"; schedule()
    }
    func report(_ error: Error) { message = error.localizedDescription }
    private func invalidate() { generation = UUID(); refreshTask?.cancel(); refreshTask = nil; isRefreshing = false }
    func refreshIfNeeded(using model: ScheduleModel, force: Bool = false) async {
        guard !isRefreshing else { return }
        // A cold background launch can precede the first unlock; retry Keychain on foreground entry.
        do { subscription = try store.load() } catch { message = error.localizedDescription; return }
        guard let record = subscription, record.shouldRefresh(at: Date(), force: force) else { schedule(); return }
        isRefreshing = true; message = "正在检查订阅…"
        let token = generation
        let job = Task { @MainActor in
            defer { if self.generation == token { self.isRefreshing = false; self.refreshTask = nil; self.schedule() } }
            do {
                let cached = model.snapshot != nil && model.snapshot?.isCleared == false && model.snapshot?.isDemo == false
                let result = try await self.client.fetch(record.url.absoluteString, etag: cached ? record.etag : nil, lastModified: cached ? record.lastModified : nil)
                try Task.checkCancellation()
                guard self.generation == token, self.subscription?.id == record.id else { return }
                if result.courses == nil && !cached { throw ICSFeedError.unexpectedNotModified }
                if let courses = result.courses {
                    _ = try ManualCourseEditor.replacingImported(courses, semester: record.semester, current: model.snapshot, origin: "preview", revision: 1)
                }
                var next = record; next.lastAttemptAt = Date(); next.lastCheckedAt = next.lastAttemptAt; next.lastError = nil
                next.etag = result.etag; next.lastModified = result.lastModified
                if result.courses != nil { next.lastUpdatedAt = next.lastAttemptAt }
                try self.store.save(next)
                do {
                    if let courses = result.courses { try model.importCourses(courses, semester: record.semester, keepSubscription: true) }
                    else { try model.markSubscriptionChecked() }
                } catch { try? self.store.save(record); throw error }
                self.subscription = next
                self.message = result.courses == nil ? "已检查，订阅内容未变化" : "订阅已更新并同步"
            } catch {
                guard self.generation == token, self.subscription?.id == record.id, !Task.isCancelled else { return }
                var failed = record; failed.lastAttemptAt = Date(); failed.lastError = error.localizedDescription
                try? self.store.save(failed); self.subscription = failed
                self.message = error.localizedDescription
            }
        }
        refreshTask = job
        await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
    }
    private func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
        guard let record = subscription, record.automatic else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = max(Date().addingTimeInterval(60), (record.lastAttemptAt ?? Date()).addingTimeInterval(ICSSubscription.refreshInterval))
        try? BGTaskScheduler.shared.submit(request)
    }
}
#if DEBUG
private final class FixtureFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let notModified = request.value(forHTTPHeaderField: "If-None-Match") == "\"fixture-v1\""
        let html = request.url?.path == "/not-calendar"
        let status = notModified ? 304 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": html ? "text/html" : "text/calendar", "ETag": "\"fixture-v1\""])!
        let cal = SchoolClock.calendar, day = cal.startOfDay(for: Date())
        let start = cal.date(bySettingHour: 16, minute: 0, second: 0, of: day)!
        let content = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nSUMMARY:Subscribed Lab\r\nLOCATION:B302\r\nDTSTART:\(SchoolClock.format(start, "yyyyMMdd'T'HHmmss"))\r\nDTEND:\(SchoolClock.format(start.addingTimeInterval(3600), "yyyyMMdd'T'HHmmss"))\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !notModified { client?.urlProtocol(self, didLoad: Data((html ? "<html>login</html>" : content).utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
