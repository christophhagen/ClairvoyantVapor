import XCTest
import XCTVapor
import Vapor
import ClairvoyantVapor
import ClairvoyantClient
@testable import Clairvoyant

final class ClairvoyantVaporTests: XCTestCase {

    private var temporaryDirectory: URL {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    var logFolder: URL {
        temporaryDirectory.appendingPathComponent("logs")
    }

    override func setUp() async throws {
        try removeAllFiles()
    }

    override func tearDown() async throws {
        try removeAllFiles()
    }

    private func removeAllFiles() throws {
        let url = logFolder
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        MetricObserver.standard = nil
    }
    
    func testMetricList() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())

        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()

        try app.test(.POST, "metrics/list", headers: [ServerRoute.headerAccessToken : ""], afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: [MetricInfo] = try decoder.decode(from: body)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.id, "log")
            XCTAssertEqual(result.first?.dataType, .string)
        })
    }

    func testAllLastValues() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        await observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()

        try app.test(.POST, "metrics/last/all", headers: [ServerRoute.headerAccessToken : ""], afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: [String : Data] = try decoder.decode(from: body)
            XCTAssertEqual(result.count, 1)
            guard let data = result["log".hashed()] else {
                XCTFail()
                return
            }
            let decoded: Timestamped<String> = try decoder.decode(from: data)
            XCTAssertEqual(decoded.value, "test")
        })
    }

    func testLastValue() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        await observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()
        let hash = "log".hashed()

        try app.test(.POST, "metrics/last/\(hash)", headers: [ServerRoute.headerAccessToken : ""], afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: Timestamped<String> = try decoder.decode(from: body)
            XCTAssertEqual(result.value, "test")
        })
    }

    func testAccessToken() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let accessToken = "mySecret"
        let token = ScopedAccessToken(
            token: accessToken,
            permissions: [.last],
            accessibleMetrics: ["log"],
            inaccessibleMetrics: ["other"])
        let provider = VaporMetricProvider(observer: observer, accessManager: token)
        let other: Metric<String> = observer.addMetric(id: "other")
        try await other.update("more")

        await observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()

        try app.test(.POST, "metrics/last/\("log".hashed())",
                     headers: [ServerRoute.headerAccessToken : accessToken],
                     afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: Timestamped<String> = try decoder.decode(from: body)
            XCTAssertEqual(result.value, "test")
        })

        try app.test(.POST, "metrics/last/\("other".hashed())",
                     headers: [ServerRoute.headerAccessToken : accessToken],
                     afterResponse: { res in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    func testHistory() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        await observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()
        let hash = "log".hashed()
        let request = MetricHistoryRequest(start: .distantPast, end: .distantFuture)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let body = try encoder.encode(request)

        try app.test(.POST, "metrics/history/\(hash)",
                     headers: [ServerRoute.headerAccessToken : ""],
                     body: .init(data: body),
                     afterResponse: { res in

            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result = try decoder.decode([Timestamped<String>].self, from: body)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.value, "test")
        })
    }
    
    func testHistoryBatch() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        let metric: Metric<Int> = provider.observer.addMetric(id: "int")
        
        // Need to ensure that decoded dates are the same
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970)
        let values = (1...100).reversed().map {
            Timestamped(value: $0, timestamp: now.advanced(by: TimeInterval(-$0)))
        }
        try await metric.update(values)
        
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()
        let hash = "int".hashed()
        let request = MetricHistoryRequest(start: .now, end: .distantPast, limit: 100)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let body = try encoder.encode(request)

        try app.test(.POST, "metrics/history/\(hash)",
                     headers: [ServerRoute.headerAccessToken : ""],
                     body: .init(data: body),
                     afterResponse: { res in

            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let newestBatch: [Timestamped<Int>] = try decoder.decode(from: body)
            XCTAssertEqual(newestBatch.first!, values.last!)
            XCTAssertEqual(newestBatch, values.suffix(100).reversed())
        })
    }

    func testScopedTokenFromJSON() throws {
        let token = ScopedAccessToken(
            token: "some".hashed().base64String(),
            permissions: [.history, .last, .list],
            accessibleMetrics: ["metric1", "some.status"],
            inaccessibleMetrics: ["hidden", "private"] )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(token)
        let expectedData = jsonData.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ScopedAccessToken.self, from: expectedData)
        let decoded2 = try decoder.decode(ScopedAccessToken.self, from: data)
        XCTAssertEqual(decoded, token)
        XCTAssertEqual(decoded2, token)
    }

    func testAccessProviders() throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())

        _ = VaporMetricProvider(observer: observer, accessManager: "MySecret")
        _ = VaporMetricProvider(observer: observer, accessManager: ["MySecret", "MyOtherSecret"])
        _ = VaporMetricProvider(observer: observer, accessManager: Set(["MySecret", "MyOtherSecret"]))
        let token1 = ScopedAccessToken(token: "MySecret", permissions: [.list])
        let token2 = ScopedAccessToken(token: "MyOtherSecret", permissions: [.list])
        _ = VaporMetricProvider(observer: observer, accessManager: token1)
        _ = VaporMetricProvider(observer: observer, accessManager: [token1, token2])
        _ = VaporMetricProvider(observer: observer, accessManager: Set([token1, token2]))
    }
}

private let jsonData =
"""
{
  "permissions" : ["history", "last", "list"],
  "token" : "YTZiNDZkZDBkMWFlNWU4NmNiYzhmMzdlNzVjZWViNjc=",
  "inaccessibleMetrics" : ["hidden", "private"],
  "accessibleMetrics" : ["metric1", "some.status"]
}
"""
