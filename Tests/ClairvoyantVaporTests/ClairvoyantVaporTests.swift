import XCTest
import XCTVapor
import Vapor
import ClairvoyantVapor
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
        observer.log("test")
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
        observer.log("test")
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

    func testHistory() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
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
}
