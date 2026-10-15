import Foundation

public enum ICSFeedError: LocalizedError, Equatable {
    case invalidURL, tooLarge, invalidContent, status(Int), network, unexpectedNotModified
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "请输入有效的 HTTPS 或 webcal:// 订阅链接，不含用户名和密码"
        case .tooLarge: "订阅文件超过 4 MB，请缩小导出范围"
        case .invalidContent: "链接未返回有效的 UTF-8 ICS 日历，请使用日历文件的直接下载链接"
        case .status(let code): "订阅服务器返回 HTTP \(code)，请检查链接是否有效或已过期"
        case .network: "订阅下载失败，请检查网络后重试；原课表已保留"
        case .unexpectedNotModified: "订阅缓存缺失，请重新下载链接"
        }
    }
}
public enum ICSFeedURL {
    public static func normalize(_ value: String) throws -> URL {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { $0.isNewline }), var parts = URLComponents(string: text),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { throw ICSFeedError.invalidURL }
        if parts.scheme?.lowercased() == "webcal" { parts.scheme = "https" }
        guard parts.scheme?.lowercased() == "https" else { throw ICSFeedError.invalidURL }
        parts.scheme = "https"; parts.fragment = nil
        guard let url = parts.url else { throw ICSFeedError.invalidURL }
        return url
    }
}
public struct ICSFeedDownload: Sendable {
    public let url: URL
    /// nil means HTTP 304; an empty array means a valid calendar with no timed events.
    public let courses: [CourseOccurrence]?
    public let etag: String?
    public let lastModified: String?
    public init(url: URL, courses: [CourseOccurrence]?, etag: String?, lastModified: String?) {
        self.url = url; self.courses = courses; self.etag = etag; self.lastModified = lastModified
    }
}
public struct ICSSubscription: Codable, Equatable, Sendable, Identifiable {
    public static let refreshInterval: TimeInterval = 6 * 3600
    public var id: UUID
    public var url: URL
    public var semester: Semester
    public var automatic: Bool
    public var etag: String?
    public var lastModified: String?
    public var lastCheckedAt: Date?
    public var lastUpdatedAt: Date?
    public var lastAttemptAt: Date?
    public var lastError: String?
    public init(url: URL, semester: Semester, automatic: Bool = true) throws {
        self.id = UUID(); self.url = try ICSFeedURL.normalize(url.absoluteString)
        self.semester = semester; self.automatic = automatic
    }
    public func shouldRefresh(at now: Date, force: Bool = false) -> Bool {
        if force { return true }
        guard automatic else { return false }
        guard let last = lastAttemptAt ?? lastCheckedAt else { return true }
        return now.timeIntervalSince(last) >= Self.refreshInterval
    }
}
private final class FeedRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https", (try? ICSFeedURL.normalize(url.absoluteString)) != nil else { completionHandler(nil); return }
        var clean = request
        clean.setValue(nil, forHTTPHeaderField: "Authorization"); clean.setValue(nil, forHTTPHeaderField: "Cookie")
        if response.url?.host != url.host {
            clean.setValue(nil, forHTTPHeaderField: "If-None-Match"); clean.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
        }
        completionHandler(clean)
    }
}
public actor ICSFeedClient {
    private let session: URLSession
    private let redirects = FeedRedirectPolicy()
    public static let maximumBytes = 4_000_000
    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.httpShouldSetCookies = false; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
    }
    public func fetch(_ address: String, etag: String? = nil, lastModified: String? = nil) async throws -> ICSFeedDownload {
        let url = try ICSFeedURL.normalize(address)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("text/calendar, application/octet-stream;q=0.8", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, let finalURL = http.url, finalURL.scheme?.lowercased() == "https",
                  (try? ICSFeedURL.normalize(finalURL.absoluteString)) != nil else { throw ICSFeedError.network }
            let tag = http.value(forHTTPHeaderField: "ETag"), modified = http.value(forHTTPHeaderField: "Last-Modified")
            if http.statusCode == 304 {
                guard etag != nil || lastModified != nil else { throw ICSFeedError.unexpectedNotModified }
                return ICSFeedDownload(url: url, courses: nil, etag: tag ?? etag, lastModified: modified ?? lastModified)
            }
            guard http.statusCode == 200 else { throw ICSFeedError.status(http.statusCode) }
            guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw ICSFeedError.tooLarge }
            var data = Data(); data.reserveCapacity(min(max(Int(response.expectedContentLength), 0), Self.maximumBytes))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumBytes else { throw ICSFeedError.tooLarge }
                data.append(byte)
            }
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")),
                  text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("BEGIN:VCALENDAR") else { throw ICSFeedError.invalidContent }
            let courses = try ICSParser().parse(text)
            return ICSFeedDownload(url: url, courses: courses, etag: tag, lastModified: modified)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ICSFeedError { throw error }
        catch let error as ScheduleError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // URLSession errors can embed secret query parameters; never expose them to the UI/log.
            throw ICSFeedError.network
        }
    }
}
