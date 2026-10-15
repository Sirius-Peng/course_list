import Foundation
import XCTest
@testable import ScheduleCore

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (Int, Data))?
    static func install(_ value: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }; handler = value
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let callback = Self.handler; Self.lock.unlock()
        do {
            let (status, data) = try callback!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class BITLoginClientTests: XCTestCase {
    func testHealthCheckWithoutCredentials() async throws {
        StubProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data(#"{"message":"BIT Login Services API is running"}"#.utf8))
        }
        let result = try await client().healthCheck()
        XCTAssertEqual(result, "认证服务连接正常")
    }
    func client() throws -> BITLoginClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return try BITLoginClient(baseURL: URL(string: "https://fixture.test")!, session: URLSession(configuration: config))
    }
    func json(_ value: String) -> Data { Data(value.utf8) }
    func testChallengeSMSAndDownloadContract() async throws {
        StubProtocol.install { request in
            switch request.url!.path {
            case "/api/auth/start":
                XCTAssertEqual(request.httpMethod, "POST")
                return (202, Data(#"{"challenge_id":"test-1","access_token":"token","status":"waiting_sms","expires_in":300,"masked_phone":"138****0000"}"#.utf8))
            case "/api/auth/test-1/sms":
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Challenge-Token"), "token")
                return (200, Data(#"{"challenge_id":"test-1","status":"authenticated","expires_in":1800,"ready_services":["jxzxehall"]}"#.utf8))
            case "/api/jxzxehall/schedule_ics":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
                return (200, Data(#"{"url":"https://download.test/term.ics","note":"fixture"}"#.utf8))
            case "/term.ics":
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "X-Challenge-Token"))
                return (200, Data("BEGIN:VCALENDAR\nEND:VCALENDAR".utf8))
            default: return (200, Data(#"{"status":"deleted"}"#.utf8))
            }
        }
        let c = try client(), start = try await c.start(username: "fixture", password: "fixture")
        XCTAssertEqual(start.status, "waiting_sms")
        let end = try await c.submit(code: "123456", type: "sms"); XCTAssertTrue(end.authenticated)
        let text = try await c.downloadSchedule(term: "2026-2027-1"); XCTAssertTrue(text.contains("VCALENDAR"))
        await c.cancel()
    }
    func testCaptchaPollingEnvelopeAndNoRepeatedPassword() async throws {
        StubProtocol.install { request in
            if request.url!.path == "/api/auth/start" {
                return (202, Data(#"{"detail":{"challenge_id":"test-2","access_token":"token","status":"waiting_captcha","expires_in":300}}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Challenge-Token"), "token")
            return (200, Data(#"{"challenge_id":"test-2","status":"authenticated","expires_in":1800,"ready_services":["jxzxehall"]}"#.utf8))
        }
        let c = try client(); _ = try await c.start(username: "fixture", password: "fixture")
        let result = try await c.submit(code: "abc1", type: "captcha"); XCTAssertTrue(result.authenticated)
        let poll = try await c.poll(); XCTAssertTrue(poll.authenticated)
    }
    func testNoTokenRejected() async throws {
        StubProtocol.install { _ in (202, Data(#"{"challenge_id":"test","status":"running","expires_in":300}"#.utf8)) }
        do { _ = try await client().start(username: "fixture", password: "fixture"); XCTFail("Missing token accepted") } catch {}
    }
    func testServiceUnavailableDoesNotPretendSuccess() async throws {
        StubProtocol.install { _ in (503, Data(#"{"detail":"maintenance"}"#.utf8)) }
        do { _ = try await client().start(username: "fixture", password: "fixture"); XCTFail("503 accepted") } catch {}
    }
    func testInvalidServerAndCode() async throws {
        XCTAssertThrowsError(try BITLoginClient(baseURL: URL(string: "http://fixture.test")!))
        StubProtocol.install { _ in (202, Data(#"{"challenge_id":"test","access_token":"token","status":"waiting_sms","expires_in":300}"#.utf8)) }
        let c = try client(); _ = try await c.start(username: "fixture", password: "fixture")
        do { _ = try await c.submit(code: "abc", type: "sms"); XCTFail("Invalid SMS accepted") } catch {}
    }
}
