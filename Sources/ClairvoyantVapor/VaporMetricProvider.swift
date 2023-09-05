import Foundation
import Vapor
import Clairvoyant

public final class VaporMetricProvider {

    /// The authentication manager for access to metric information
    public let accessManager: MetricRequestAccessManager

    /// The metric observer exposed through vapor
    public let observer: MetricObserver

    /// The encoder to use for the response data.
    public let encoder: BinaryEncoder

    /// The encoder to use for the request body decoding.
    public let decoder: BinaryDecoder

    /// The first path component of the routes
    private var subPath = ""

    /**
     - Parameter observer: The metric observer to expose through vapor
     - Parameter accessManager: The handler of authentication to access metric data
     - Parameter encoder: The encoder to use for the response data. Defaults to the encoder of the observer
     - Parameter decoder: The decoder to use for the request body decoding. Defaults to the decoder of the observer
     */
    public init(observer: MetricObserver, accessManager: MetricRequestAccessManager, encoder: BinaryEncoder? = nil, decoder: BinaryDecoder? = nil) {
        self.accessManager = accessManager
        self.observer = observer
        self.encoder = encoder ?? observer.encoder
        self.decoder = decoder ?? observer.decoder
    }

    private func checkAccessToAllMetrics(for request: Request, on route: ServerRoute) throws -> [MetricIdHash] {
        let list = self.observer.getAllMetricHashes()
        return try self.accessManager.getAllowedMetrics(for: request, on: route, accessing: list)
    }

    private func checkAccess(_ request: Request, on route: ServerRoute, metric: MetricIdHash) throws {
        guard try accessManager.getAllowedMetrics(for: request, on: route, accessing: [metric])
            .contains(metric) else {
            throw MetricError.accessDenied
        }
    }

    private func getAccessibleMetric(_ request: Request, route: ServerRoute.Prefix) throws -> GenericMetric {
        let metricIdHash = try request.metricIdHash()
        let metric = try observer.getMetricByHash(metricIdHash)
        let fullRoute = route.with(hash: metricIdHash)
        try checkAccess(request, on: fullRoute, metric: metricIdHash)
        return metric
    }

    private func encode<T>(_ result: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            observer.log("Failed to encode response: \(error)")
            throw MetricError.failedToEncode
        }
    }

    /**
     Register the routes to access the properties.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "metrics") {
        self.subPath = subPath
        registerMetricListRoute(app)
        registerLastValueCollectionRoute(app)
        registerLastValueRoute(app)
        registerHistoryRoute(app)
        registerRemotePushRoute(app)
        registerExtendedInfoRoute(app)
    }

    /**
     The route to access the list of registered metrics.

     - Type: `POST`
     - Path: `/metrics/list`
     - Headers:
     - `token` : The access token for the client
     - Response: `[MetricDescription]`
     */
    func registerMetricListRoute(_ app: Application) {
        register(route: .getMetricList, to: app) { (provider, request) in
            let allowedMetrics = try provider.checkAccessToAllMetrics(for: request, on: .getMetricList)
            let filteredResult = provider.observer.getListOfRecordedMetrics()
                .filter { allowedMetrics.contains($0.key) }
                .map { $0.value }
            return try provider.encode(filteredResult)
        }
    }

    /**
     The route to access the last values of all metrics.

     - Type: `POST`
     - Path: `/metrics/last/all`
     - Headers:
     - `token` : The access token for the client
     - Response: `[MetricIdHash : Data]`, a mapping between ID hash and encoded timestamped value.
     */
    func registerLastValueCollectionRoute(_ app: Application) {
        register(route: .allLastValues, to: app) { (provider, request) in
            let allowedMetrics = try provider.checkAccessToAllMetrics(for: request, on: .allLastValues)
            let values = await provider.observer.getLastValuesOfAllMetrics()
                .filter { allowedMetrics.contains($0.key) }
            return try provider.encode(values)
        }
    }

    /**
     The route to access the extended info (last values and info) of all metrics.

     - Type: `POST`
     - Path: `subPath` + ``ServerRoute.Prefix.extendedInfoList``
     - Headers:
     - `token` : The access token for the client (if using a ``MetricAccessManager``)
     - Response: `[MetricIdHash : Data]`, a mapping between ID hash and encoded timestamped value.
     */
    func registerExtendedInfoRoute(_ app: Application) {
        register(route: .extendedInfoList, to: app) { (provider, request) in
            let allowedMetrics = try provider.checkAccessToAllMetrics(for: request, on: .extendedInfoList)
            let values = await provider.observer.getExtendedDataOfAllRecordedMetrics()
                .filter { allowedMetrics.contains($0.key) }
            return try provider.encode(values)
        }
    }

    /**
     The route to access the last value of a metric.

     - Type: `POST`
     - Path: `/metrics/last/<ID_HASH>`
     - Headers:
     - `token` : The access token for the client
     - Response: `Timestamped<T>`, the encoded timestamped value.
     - Errors: `410`, if no value is available
     */
    func registerLastValueRoute(_ app: Application) {
        register(route: .lastValue, to: app) { (provider, request) in
            let metric = try provider.getAccessibleMetric(request, route: .lastValue)
            return try await metric.lastValueData()
                .unwrap(or: MetricError.noValueAvailable)
        }
    }

    /**
     The route to access historic values of a metric.

     - Type: `POST`
     - Path: `/metrics/history/<ID_HASH>`
     - Headers:
     - `token` : The access token for the client
     - Body: `MetricHistoryRequest`
     - Response: `[Timestamped<T>]`, the encoded timestamped values.
     */
    func registerHistoryRoute(_ app: Application) {
        register(route: .metricHistory, to: app) { (provider, request) in
            let metric = try provider.getAccessibleMetric(request, route: .metricHistory)
            let range = try request.decodeBody(as: MetricHistoryRequest.self, using: self.decoder)
            return await metric.encodedHistoryData(from: range.start, to: range.end, maximumValueCount: range.limit)
        }
    }

    /**
     The route to update a metric from a remote.

     - Type: `POST`
     - Path: `/metrics/push/<ID_HASH>`
     - Headers:
     - `token` : The access token for the client
     - Body: `[Timestamped<T>]`
     */
    func registerRemotePushRoute(_ app: Application) {
        register(route: .pushValueToMetric, to: app) { (provider, request) in
            let metric = try provider.getAccessibleMetric(request, route: .pushValueToMetric)
            guard metric.canBeUpdatedByRemote else {
                throw Abort(.expectationFailed)
            }

            // Save value for metric
            let valueData = try request.bodyData.unwrap(or: Abort(.badRequest))
            try await metric.addDataFromRemote(valueData)
            return Data()
        }
    }

    /**
     Helper function to register routes with a weak reference to `self`
     */
    private func register(route: ServerRoute.Prefix, to app: Application, closure: @escaping (_ self: VaporMetricProvider, Request) async throws -> Data) {
        app.post([.constant(subPath)] + route.path)  { [weak self] request -> Response in
            guard let self else {
                throw Abort(.internalServerError)
            }
            do {
                let data = try await closure(self, request)
                return .init(status: .ok, body: .init(data: data))
            } catch let error as MetricError {
                return Response(status: error.status)
            } catch {
                throw error
            }
        }
    }
}
