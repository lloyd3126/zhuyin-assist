import Foundation

enum HistoryOutcome: String {
    case modified = "已修改"
    case unchanged = "無需修改"
    case notRestored = "未能還原"
    case cancelled = "已取消"
    case failure = "失敗"
}
func historyOutcome(for outcome: CorrectionOutcome, original: String, confirmed: String?) -> HistoryOutcome {
    switch outcome {
    case .cancelled: return .cancelled
    case .failure: return .failure
    case .success:
        guard let confirmed else { return .failure }
        if confirmed == original { return hasKeyboardRecoveryInput(original) ? .notRestored : .unchanged }
        return .modified
    }
}

struct CorrectionHistoryEntry {
    let id: UUID
    let date: Date
    let appName: String
    let original: String
    let corrected: String?
    let outcome: HistoryOutcome
    let elapsed: TimeInterval
    let detail: String
}

// Session-only: no document contents are serialized or written to disk.
final class CorrectionHistoryStore {
    private(set) var entries: [CorrectionHistoryEntry] = []
    func append(_ entry: CorrectionHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 20 { entries.removeLast(entries.count - 20) }
    }
    func clear() { entries.removeAll() }
}

struct DiagnosticCheck {
    let title: String
    let passed: Bool
    let detail: String
}

struct DiagnosticViewState {
    let checks: [DiagnosticCheck]
    let latest: String
    let apiStatus: String
    let apiBusy: Bool
    let correctionBusy: Bool
    let modeActive: Bool
    let report: String
}

struct DiagnosticEvent {
    let date: Date
    let message: String
}

final class DiagnosticLog {
    private(set) var events: [DiagnosticEvent] = []
    private(set) var modeUntil: Date?
    func startMode(at date: Date = Date()) { modeUntil = date.addingTimeInterval(30) }
    func stopMode() { modeUntil = nil }
    func isActive(at date: Date = Date()) -> Bool { modeUntil.map { date < $0 } ?? false }
    func record(_ message: String, at date: Date = Date()) {
        events.append(DiagnosticEvent(date: date, message: message))
        if events.count > 50 { events.removeFirst(events.count - 50) }
    }
    func report(version: String, installPath: String, checks: [DiagnosticCheck], apiStatus: String) -> String {
        let date = DateFormatter(); date.dateFormat = "HH:mm:ss"
        var lines = ["Gemini 段落校正診斷報告", "版本：\(version)", "安裝位置：\(installPath)",
                     "模型：\(model)", "此報告不包含 Gemini 金鑰、原文或校正結果。", ""]
        lines += checks.map { "\($0.passed ? "✓" : "!") \($0.title)：\($0.detail)" }
        lines += ["Gemini 測試：\(apiStatus)", "", "最近處理步驟："]
        lines += events.map { "\(date.string(from: $0.date))  \($0.message)" }
        return lines.joined(separator: "\n")
    }
}

// Uses the existing correction request/response contract with a fixed sentence.
// Never captures a text field, replaces a document, or stores a key in a report.
final class GeminiConnectionTest {
    static let sentence = "這個輸入法的選自不太準，請幫我檢查錯自。"
    static let expected = "這個輸入法的選字不太準，請幫我檢查錯字。"
    var onChange: (() -> Void)?
    private(set) var busy = false
    private(set) var status = "尚未測試"
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let delegate = GoogleSessionDelegate()
    private let configurationFactory: () -> URLSessionConfiguration
    init(configurationFactory: @escaping () -> URLSessionConfiguration = { .ephemeral }) {
        self.configurationFactory = configurationFactory
    }

    func start(key: String) {
        guard !busy else { return }
        busy = true; status = "正在測試 Gemini…"; onChange?()
        let started = ProcessInfo.processInfo.systemUptime
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody(Self.sentence))
        let config = configurationFactory()
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 15
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.busy else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                do {
                    guard error == nil else { throw fail("Gemini 連線中斷或回應逾時，請稍後再試。") }
                    guard let data, let response = response as? HTTPURLResponse else { throw fail("Gemini 沒有提供有效回應。") }
                    guard response.statusCode == 200 else { throw httpError(response.statusCode, data: data) }
                    let corrected = try parseResponse(data, original: Self.sentence)
                    self.status = Self.resultMessage(corrected: corrected, elapsed: elapsed)
                } catch { self.status = error.localizedDescription }
                self.busy = false; self.task = nil
                self.session?.finishTasksAndInvalidate(); self.session = nil
                self.onChange?()
            }
        }
        task?.resume()
    }
    static func resultMessage(corrected: String, elapsed: TimeInterval) -> String {
        let time = String(format: "%.1f 秒", elapsed)
        if corrected == expected {
            return "連線成功，校正測試通過 · \(time)"
        }
        return "連線成功，但校正結果未符合完整測試句 · \(time)"
    }
    func showFailure(_ message: String) {
        guard !busy else { return }
        status = message; onChange?()
    }
    func cancel() {
        busy = false; task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
    }
    deinit { cancel() }
}

func troubleshootingModelTest() throws {
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw fail(message) }
    }
    let history = CorrectionHistoryStore()
    try check(historyOutcome(for: .success, original: "選自", confirmed: "選字") == .modified, "Confirmed change must be classified as modified")
    try check(historyOutcome(for: .success, original: "選字", confirmed: "選字") == .unchanged, "Confirmed identical text must be classified as unchanged")
    let typoKeys = "5qu/6eji32k7gj bj4z83u.3e.4x04"
    try check(historyOutcome(for: .success, original: typoKeys, confirmed: typoKeys) == .notRestored, "Unrestored keyboard input must not be labeled as no correction needed")
    let multilineKeys = "第一段\n\(typoKeys)"
    try check(historyOutcome(for: .success, original: multilineKeys, confirmed: multilineKeys) == .notRestored, "Unrestored keyboard lines must be identified inside a multiline selection")
    let fenced = "```\n\(typoKeys)\n```"
    try check(historyOutcome(for: .success, original: fenced, confirmed: fenced) == .unchanged, "Protected code must not be labeled as an attempted keyboard recovery")
    try check(historyOutcome(for: .cancelled, original: "選自", confirmed: nil) == .cancelled, "Cancelled result must be classified as cancelled")
    try check(historyOutcome(for: .failure, original: "選自", confirmed: nil) == .failure, "Failed result must be classified as failed")
    try check(historyOutcome(for: .success, original: "選自", confirmed: nil) == .failure, "Unconfirmed result must never claim a modification")
    let secretDocument = "PRIVATE_DOCUMENT_SENTINEL"
    for i in 0..<25 {
        history.append(CorrectionHistoryEntry(id: UUID(), date: Date(), appName: "Dummy App", original: secretDocument,
            corrected: "result \(i)", outcome: .modified, elapsed: 1, detail: "已完成"))
    }
    try check(history.entries.count == 20 && history.entries.first?.corrected == "result 24", "History must retain newest 20 entries")
    let log = DiagnosticLog(); let now = Date(timeIntervalSince1970: 100)
    log.startMode(at: now)
    try check(log.isActive(at: now.addingTimeInterval(29)) && !log.isActive(at: now.addingTimeInterval(30)), "Diagnostic mode must expire after 30 seconds")
    log.stopMode(); try check(!log.isActive(at: now), "Stop must deactivate diagnostics")
    for i in 0..<60 { log.record("步驟 \(i)", at: now) }
    try check(log.events.count == 50 && log.events.first?.message == "步驟 10", "Diagnostic log must be bounded")
    let report = log.report(version: "test", installPath: "/Applications/Dummy.app", checks: [], apiStatus: "尚未測試")
    try check(!report.contains(secretDocument) && !report.contains("result 24"), "Report must exclude history originals and results")
    try check(GeminiConnectionTest.resultMessage(corrected: GeminiConnectionTest.expected, elapsed: 1).contains("測試通過"), "Probe must distinguish the complete corrected test sentence")
    for invalid in [GeminiConnectionTest.sentence, "選字，錯字。", "這個輸入法的選字不太準。錯字。"] {
        try check(GeminiConnectionTest.resultMessage(corrected: invalid, elapsed: 1).contains("未符合"), "An incomplete or unchanged test response must not claim correction success")
    }
    history.clear(); try check(history.entries.isEmpty, "Clear must remove all session history")
    try geminiConnectionCallbackTest()
    print("PASS: session history limit/clear, diagnostic expiry/bounds/privacy, and Gemini test result classification; dummy data only.")
}

private final class GeminiTestURLProtocol: URLProtocol {
    static var statusCode = 200
    static var body = Data()
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func geminiConnectionCallbackTest() throws {
    func response(_ text: String) throws -> Data {
        let encoded = String(data: try JSONSerialization.data(withJSONObject: ["corrected_text": text]), encoding: .utf8)!
        return try JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": encoded]]]]]])
    }
    let tests: [(Int, Data, String)] = [
        (200, try response(GeminiConnectionTest.expected), "測試通過"),
        (200, try response("選字，錯字。"), "未符合"),
        (200, try response(GeminiConnectionTest.sentence), "未符合"),
        (200, Data("invalid-json".utf8), "沒有完成"),
        (429, Data(), "暫時無法"),
        (401, Data(), "金鑰無效")
    ]
    for (code, body, expected) in tests {
        GeminiTestURLProtocol.statusCode = code; GeminiTestURLProtocol.body = body
        let probe = GeminiConnectionTest(configurationFactory: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [GeminiTestURLProtocol.self]
            return config
        })
        var complete = false
        probe.onChange = { if !probe.busy { complete = true } }
        probe.start(key: "dummy-test-credential")
        let deadline = Date().addingTimeInterval(3)
        while !complete && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard complete, probe.status.contains(expected), !probe.status.contains("dummy-test-credential") else {
            throw fail("Gemini callback test failed for HTTP \(code): \(probe.status)")
        }
        guard GeminiTestURLProtocol.requests.last?.value(forHTTPHeaderField: "x-goog-api-key") == "dummy-test-credential" else {
            throw fail("Gemini key must be sent only in the intended request header")
        }
        probe.onChange = nil
    }
    GeminiTestURLProtocol.requests.removeAll()
    print("PASS: Gemini request/URLSession callbacks for success, unchanged/incomplete/malformed replies, 401 and 429; intercepted requests, no external network.")
}
