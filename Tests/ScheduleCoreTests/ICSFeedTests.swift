import Foundation
import XCTest
@testable import ScheduleCore

private final class FeedStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var callback: ((URLRequest) throws -> (Int, [String: String], Data, URL?))?
    static func install(_ callback: @escaping (URLRequest) throws -> (Int, [String: String], Data, URL?)) {
        lock.lock(); defer { lock.unlock() }; self.callback = callback
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let callback = Self.callback!; Self.lock.unlock()
        do {
            let (code, headers, data, finalURL) = try callback(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: finalURL ?? request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class ICSFeedTests: XCTestCase {
    let address = "https://fixture.test/feed?token=private-fixture"
    var calendar: Data { Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nSUMMARY:订阅课程\r\nLOCATION:A201\r\nDTSTART;TZID=Asia/Shanghai:20261015T080000\r\nDTEND;TZID=Asia/Shanghai:20261015T094000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8) }
    func client() -> ICSFeedClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FeedStub.self]
        return ICSFeedClient(session: URLSession(configuration: config))
    }
    func testHTTPSLinkKeepsSignedQueryWithoutRequiringICSExtension() throws {
        XCTAssertEqual(try ICSFeedURL.normalize("  " + address + "  ").absoluteString, address)
    }
    func testWebcalNormalizesToHTTPSAndRemovesFragment() throws {
        XCTAssertEqual(try ICSFeedURL.normalize("webcal://fixture.test/feed?token=abc#local").absoluteString, "https://fixture.test/feed?token=abc")
    }
    func testInvalidSchemesAndEmbeddedCredentialsRejected() {
        for text in ["http://fixture.test/a.ics", "file:///a.ics", "ftp://fixture.test/a.ics", "https:///", "https://u:p@fixture.test/a.ics", "https://fixture.test/a\nb", "not a link"] {
            XCTAssertThrowsError(try ICSFeedURL.normalize(text), text)
        }
    }
    func testDownloadParsesICSAndCapturesValidatorsWithoutSchoolCredentials() async throws {
        let data = calendar
        FeedStub.install { request in
            XCTAssertEqual(request.url?.query, "token=private-fixture"); XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "X-Challenge-Token"))
            return (200, ["Content-Type":"text/calendar", "ETag":"\"v1\"", "Last-Modified":"Thu, 15 Oct 2026 00:00:00 GMT"], data, nil)
        }
        let value = try await client().fetch(address)
        XCTAssertEqual(value.courses?.first?.title, "订阅课程"); XCTAssertEqual(value.courses?.first?.displayLocation, "A201")
        XCTAssertEqual(value.etag, "\"v1\""); XCTAssertNotNil(value.lastModified)
    }
    func testConditionalHTTP304DoesNotPretendToBeEmptyCalendar() async throws {
        FeedStub.install { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "yesterday")
            return (304, [:], Data(), nil)
        }
        let value = try await client().fetch(address, etag: "\"v1\"", lastModified: "yesterday")
        XCTAssertNil(value.courses); XCTAssertEqual(value.etag, "\"v1\""); XCTAssertEqual(value.lastModified, "yesterday")
    }
    func testInitialUnexpected304Rejected() async {
        FeedStub.install { _ in (304, [:], Data(), nil) }
        do { _ = try await client().fetch(address); XCTFail() } catch { XCTAssertEqual(error as? ICSFeedError, .unexpectedNotModified) }
    }
    func testHTTPFailuresDoNotLeakSubscriptionToken() async {
        FeedStub.install { _ in (403, [:], Data("secret response".utf8), nil) }
        do { _ = try await client().fetch(address); XCTFail() } catch {
            XCTAssertEqual(error as? ICSFeedError, .status(403)); XCTAssertFalse(error.localizedDescription.contains("private-fixture"))
        }
    }
    func testHTMLAndInvalidUTF8Rejected() async {
        for data in [Data("<html>login</html>".utf8), Data([0xff, 0xfe, 0x80])] {
            FeedStub.install { _ in (200, [:], data, nil) }
            do { _ = try await client().fetch(address); XCTFail() } catch { XCTAssertEqual(error as? ICSFeedError, .invalidContent) }
        }
    }
    func testAdvertisedLargeContentRejectedBeforeReading() async {
        FeedStub.install { _ in (200, ["Content-Length":"4000001"], Data(), nil) }
        do { _ = try await client().fetch(address); XCTFail() } catch { XCTAssertEqual(error as? ICSFeedError, .tooLarge) }
    }
    func testStreamingLimitRejectsUnadvertisedLargeBody() async {
        FeedStub.install { _ in (200, [:], Data(repeating: 65, count: 4_000_001), nil) }
        do { _ = try await client().fetch(address); XCTFail() } catch { XCTAssertEqual(error as? ICSFeedError, .tooLarge) }
    }
    func testInvalidFinalTransportRejected() async {
        let data = calendar
        FeedStub.install { _ in (200, [:], data, URL(string:"http://fixture.test/feed")!) }
        do { _ = try await client().fetch(address); XCTFail() } catch { XCTAssertEqual(error as? ICSFeedError, .network) }
    }
    func testEmptyCalendarIsValidAndBOMAccepted() async throws {
        FeedStub.install { _ in (200, [:], Data("\u{FEFF}BEGIN:VCALENDAR\nEND:VCALENDAR".utf8), nil) }
        let value = try await client().fetch(address); XCTAssertEqual(value.courses, [])
    }
    func testNetworkFailureSanitized() async {
        FeedStub.install { request in throw URLError(.timedOut, userInfo:[NSURLErrorFailingURLStringErrorKey:request.url!.absoluteString]) }
        do { _ = try await client().fetch(address); XCTFail() } catch {
            XCTAssertEqual(error as? ICSFeedError, .network); XCTAssertFalse(error.localizedDescription.contains("private-fixture"))
        }
    }
    func testSubscriptionPersistenceAndRefreshWindow() throws {
        let now = Date(), sem = Semester(name:"测试", firstMonday:SchoolClock.monday(containing:Date()), end:Date().addingTimeInterval(90*86400))
        var record = try ICSSubscription(url:URL(string:address)!, semester:sem)
        XCTAssertTrue(record.shouldRefresh(at:now))
        record.lastAttemptAt = now
        XCTAssertFalse(record.shouldRefresh(at:now.addingTimeInterval(3600)))
        XCTAssertTrue(record.shouldRefresh(at:now.addingTimeInterval(6*3600)))
        record.automatic = false
        XCTAssertFalse(record.shouldRefresh(at:now.addingTimeInterval(86400)))
        XCTAssertTrue(record.shouldRefresh(at:now, force:true))
        XCTAssertEqual(try JSONDecoder().decode(ICSSubscription.self, from:JSONEncoder().encode(record)),record)
    }
}
