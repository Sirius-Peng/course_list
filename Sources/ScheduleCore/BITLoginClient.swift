import Foundation

public struct AuthChallenge: Decodable, Sendable, Equatable {
    public let id: String
    public let token: String?
    public let status: String
    public let expiresIn: Int
    public let readyServices: [String]?
    public let captchaImage: String?
    public let maskedPhone: String?
    public let error: String?
    enum CodingKeys: String, CodingKey {
        case id = "challenge_id", token = "access_token", status, expiresIn = "expires_in"
        case readyServices = "ready_services", captchaImage = "captcha_image", maskedPhone = "masked_phone", error
    }
    public var requiresInput: Bool { status == "waiting_sms" || status == "waiting_captcha" }
    public var authenticated: Bool { status == "authenticated" }
}
public actor BITLoginClient {
    public let baseURL: URL
    private let session: URLSession
    private var token: String?
    private var challengeID: String?
    private var deadline: Date?
    public init(baseURL: URL, session: URLSession = .shared) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else { throw ScheduleError.invalid("登录服务地址需要是有效 HTTPS 地址") }
        self.baseURL = baseURL; self.session = session
    }
    public func healthCheck() async throws -> String {
        let data = try await request("", method: "GET")
        struct Health: Decodable { var message: String }
        let value = try JSONDecoder().decode(Health.self, from: data)
        guard value.message.contains("BIT Login") else { throw ScheduleError.invalid("此地址不是 BIT-Login 服务") }
        return "认证服务连接正常"
    }
    public func start(username: String, password: String) async throws -> AuthChallenge {
        guard !username.isEmpty, !password.isEmpty else { throw ScheduleError.invalid("请输入学号和统一认证密码") }
        let response = try await request("api/auth/start", method: "POST", body: ["username": username, "password": password, "services": ["jxzxehall"], "wait_seconds": 1])
        let challenge = try decodeChallenge(response)
        guard let token = challenge.token, !token.isEmpty else { throw ScheduleError.invalid("认证服务未返回令牌") }
        self.token = token; challengeID = challenge.id
        deadline = Date().addingTimeInterval(Double(challenge.expiresIn))
        return try check(challenge)
    }
    public func poll() async throws -> AuthChallenge {
        let id = try liveID()
        let data = try await request("api/auth/\(id)", method: "GET", tokenHeader: true)
        let result = try decodeChallenge(data)
        return try check(result)
    }
    public func submit(code: String, type: String) async throws -> AuthChallenge {
        guard ["captcha", "sms"].contains(type) else { throw ScheduleError.invalid("验证码类型无效") }
        let id = try liveID(), trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = type == "sms" ? trimmed.range(of: "^[0-9]{4,8}$", options: .regularExpression) != nil : (1...16).contains(trimmed.count) && !trimmed.contains(where: \.isWhitespace)
        guard valid else { throw ScheduleError.invalid("请输入有效验证码") }
        let data = try await request("api/auth/\(id)/\(type)", method: "POST", body: ["code": trimmed], tokenHeader: true)
        return try check(decodeChallenge(data))
    }
    public func downloadSchedule(term: String) async throws -> String {
        let id = try liveID()
        var body: [String: Any] = ["challenge_id": id]
        if !term.isEmpty { body["kksj"] = term }
        let data = try await request("api/jxzxehall/schedule_ics", method: "POST", body: body, bearer: true)
        struct LinkResponse: Decodable { var url: String }
        let response = try JSONDecoder().decode(LinkResponse.self, from: data)
        guard let url = URL(string: response.url, relativeTo: baseURL)?.absoluteURL, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw ScheduleError.invalid("课表下载链接无效") }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        // The export URL can point at another host; never attach auth credentials.
        let (ics, result) = try await session.data(for: request)
        guard let http = result as? HTTPURLResponse, http.statusCode == 200,
              ics.count <= 4_000_000, let text = String(data: ics, encoding: .utf8) else {
            throw ScheduleError.invalid("课表下载失败或文件过大，请重新拉取")
        }
        return text
    }
    public func cancel() async {
        if let id = challengeID { _ = try? await request("api/auth/\(id)", method: "DELETE", tokenHeader: true) }
        token = nil; challengeID = nil; deadline = nil
    }
    private func liveID() throws -> String {
        guard let challengeID, token != nil, let deadline, deadline > Date() else { throw ScheduleError.invalid("认证已过期，请重新登录") }
        return challengeID
    }
    private func check(_ value: AuthChallenge) throws -> AuthChallenge {
        guard value.id == challengeID, value.id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw ScheduleError.invalid("认证挑战标识不匹配")
        }
        if ["failed", "expired", "cancelled"].contains(value.status) { throw ScheduleError.invalid("统一认证失败或已过期，请重新登录") }
        guard ["running", "processing", "waiting_sms", "waiting_captcha", "authenticated"].contains(value.status), value.expiresIn > 0 else {
            throw ScheduleError.invalid("认证服务返回未知状态")
        }
        if value.authenticated, !(value.readyServices ?? []).contains("jxzxehall") { throw ScheduleError.invalid("教学中心会话尚未就绪") }
        deadline = Date().addingTimeInterval(Double(value.expiresIn))
        return value
    }
    private func decodeChallenge(_ data: Data) throws -> AuthChallenge {
        if let direct = try? JSONDecoder().decode(AuthChallenge.self, from: data) { return direct }
        struct Envelope: Decodable { var detail: AuthChallenge }
        return try JSONDecoder().decode(Envelope.self, from: data).detail
    }
    private func request(_ path: String, method: String, body: [String: Any]? = nil,
                         tokenHeader: Bool = false, bearer: Bool = false) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = method
        request.timeoutInterval = 45
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if tokenHeader { request.setValue(token, forHTTPHeaderField: "X-Challenge-Token") }
        if bearer, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, result) = try await session.data(for: request)
        guard let http = result as? HTTPURLResponse, [200, 202].contains(http.statusCode) else {
            let code = (result as? HTTPURLResponse)?.statusCode ?? 0
            throw ScheduleError.invalid("服务请求失败（HTTP \(code)），请检查服务地址和认证状态")
        }
        guard data.count <= 4_000_000 else { throw ScheduleError.invalid("服务响应过大") }
        return data
    }
}
