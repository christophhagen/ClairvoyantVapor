import Foundation
import Vapor
import Clairvoyant
import ClairvoyantClient

public final class VaporMetricProvider {

    /// The authentication manager for access to metric information
    public let accessManager: RequestAccessManager

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
    public init(observer: MetricObserver, accessManager: RequestAccessManager, encoder: BinaryEncoder? = nil, decoder: BinaryDecoder? = nil) {
        self.accessManager = accessManager
        self.observer = observer
        self.encoder = encoder ?? observer.encoder
        self.decoder = decoder ?? observer.decoder
    }

    // MARK: Access control

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

    // MARK: Coding wrappers

    private func encode<T>(_ result: T) async throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            await observer.log("Failed to encode response: \(error)")
            throw MetricError.failedToEncode
        }
    }

    private func decode<T>(_ data: Data, as type: T.Type = T.self) async throws -> T where T: Decodable {
        do {
            return try decoder.decode(from: data)
        } catch {
            await observer.log("Failed to decode request body: \(error)")
            throw MetricError.failedToDecode
        }
    }

    // MARK: Routes

    /**
     Register the routes to access the properties.
     - Parameter app: The Vapor application to register the routes with.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "metrics") {
        self.subPath = subPath

        // Route: Get list of all metrics
        multipleMetricsRoute(.getMetricList, to: app) { (provider, allowedMetrics, _) in
            let filteredResult = provider.observer.getListOfRecordedMetrics()
                .filter { allowedMetrics.contains($0.key) }
                .map { $0.value }
            return try await provider.encode(filteredResult)
        }

        // Route: Get last values of all metrics
        multipleMetricsRoute(.allLastValues, to: app) { (provider, allowedMetrics, _) in
            let values = await provider.observer.getLastValuesOfAllMetrics()
                .filter { allowedMetrics.contains($0.key) }
            return try await provider.encode(values)
        }

        // Route: Get info and last value for all metrics
        multipleMetricsRoute(.extendedInfoList, to: app) { (provider, allowedMetrics, _) in
            let values = await provider.observer.getExtendedDataOfAllRecordedMetrics()
                .filter { allowedMetrics.contains($0.key) }
            return try await provider.encode(values)
        }

        // Route: Get info of metric
        singleMetricRoute(.getMetricInfo, to: app) { (provider, metric, _) in
            try await provider.encode(metric.info)
        }

        // Route: Get last value for single metric
        singleMetricRoute(.lastValue, to: app) { (provider, metric, _) in
            try await metric.lastValueData().unwrap(or: MetricError.noValueAvailable)
        }

        // Route: Get history for single metric
        singleMetricRoute(.metricHistory, to: app) { (provider, metric, body) in
            let body = try body.unwrap(or: Abort(.badRequest))
            let range: MetricHistoryRequest = try await provider.decode(body)
            return await metric.encodedHistoryData(from: range.start, to: range.end, maximumValueCount: range.limit)
        }

        // Route: Update value for single metric
        singleMetricRoute(.pushValueToMetric, to: app) { (provider, metric, _) in
            provider.asyncScheduler.schedule {
                guard let update = provider.remoteTrackingMetrics[metric.id] else {
                    throw Abort(.expectationFailed)
                }
                await update()
            }
            return Data()
        }
    }

    // MARK: Route helper functions

    /**
     Register a route concerning a single metric.
     - Parameter route: The route to register.
     - Parameter app: The application where the route should be registered.
     - Parameter closure: The closure to execute when the route is called.
     - Parameter provider: A reference to `self`, without a strong reference to it.
     - Parameter metric: The metric accessed by the request, already authenticated.
     - Parameter body: The data of the request body.
     */
    private func singleMetricRoute(_ route: ServerRoute.Prefix, to app: Application, closure: @escaping (_ provider: VaporMetricProvider, _ metric: GenericMetric, _ body: Data?) async throws -> Data) {
        register(route: route, to: app) { (provider, request) in
            let metric = try provider.getAccessibleMetric(request, route: route)
            return try await closure(provider, metric, request.bodyData)
        }
    }

    /**
     Register a route concerning all metrics.
     - Parameter route: The route to register.
     - Parameter app: The application where the route should be registered.
     - Parameter closure: The closure to execute when the route is called.
     - Parameter provider: A reference to `self`, without a strong reference to it.
     - Parameter metric: The list of accessible metric hashes for the route.
     - Parameter body: The data of the request body.
     */
    private func multipleMetricsRoute(_ route: ServerRoute, to app: Application, closure: @escaping (_ self: VaporMetricProvider, [MetricIdHash], Data?) async throws -> Data) {
        register(route: route.prefix, to: app) { (provider, request) in
            let allowedMetrics = try provider.checkAccessToAllMetrics(for: request, on: route)
            return try await closure(provider, allowedMetrics, request.bodyData)
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

    // MARK: Remotes

    private var remoteTrackingMetrics: [MetricId : () async -> Bool] = [:]

    public var asyncScheduler: AsyncScheduler = AsyncTaskScheduler()

    /// The timeout (in seconds) for requests to notify remote observers
    public var remoteObserverNotificationTimeout: TimeInterval = 10.0

    /**
     Link a metric on a remote server to a local metric.

     This function marks the local metric as updatable by the remote.
     The remote can then issue notification to the `push` route with the local metric id, to inform the local instance about updates to the remote metric.
     The local server will then attempt to retrieve all new values on the remote server for the metric.
     - Parameter remote: The metric on the remote server
     - Parameter metric: The local metric to mirror the remote
     */
    public func allowUpdates<T>(from remote: ConsumableMetric<T>, to metric: Metric<T>) {
        guard remoteTrackingMetrics[metric.id] == nil else {
            return
        }
        remoteTrackingMetrics[metric.id] = { [weak self] in
            await self?.update(metric: metric, from: remote) ?? false
        }
    }

    /**
     Get all updates to a remote metric registered using ``allowUpdates(from:to:)``.
     - Parameter id: The id of the local metric
     */
    @discardableResult
    public func updateMetricFromRemote(_ id: MetricId) async -> Bool {
        guard let update = remoteTrackingMetrics[id] else {
            return false
        }
        return await update()
    }

    /**
     Notify a remote server when a metric value is updated.
     - Parameter metric: The metric whose updates should be forwarded
     - Parameter remoteObserver: The information about the remote server receiving the updates
     - Parameter remoteMetricId: An optional custom id of the metric on the remote server. By default, the remote id is the same as the metric id.
     - Parameter timeout: The request timeout for the push request. If unspecified, then the ``remoteObserverNotificationTimeout`` is used.
     */
    public func pushUpdates<T>(of metric: Metric<T>, to remoteObserver: RemoteMetricObserver, as remoteMetricId: String? = nil, timeout: TimeInterval? = nil) async where T: MetricValue {
        let timeout = timeout ?? remoteObserverNotificationTimeout
        let observer = self.observer
        let remoteIdHash = remoteMetricId?.hashed() ?? metric.idHash
        await metric.onChange { [weak self] _ in
            self?.asyncScheduler.schedule {
                let remoteUrl = remoteObserver.remoteUrl
                do {
                    let route = ServerRoute.pushValueToMetric(remoteIdHash)
                    let url = remoteUrl.appendingPathComponent(route.rawValue)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = timeout
                    remoteObserver.accessProvider.addAccessDataToMetricRequest(&request, route: route)

                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse else {
                        await observer.log("[\(metric.id)] Invalid response pushing value to \(remoteUrl.path): \(response)")
                        return
                    }
                    guard response.statusCode == 200 else {
                        await observer.log("[\(metric.id)] Failed to push value to \(remoteUrl.path): Response \(response.statusCode)")
                        return
                    }
                } catch {
                    await observer.log("[\(metric.id)] Failed to push value to \(remoteUrl.path): \(error)")
                }
            }
        }
    }

    private func update<T>(metric: Metric<T>, from remote: ConsumableMetric<T>) async -> Bool where T: MetricValue {
        var startDate = await metric.lastUpdate() ?? .distantPast

        do {
            while true {
                let newValues = try await remote.history(in: startDate...Date())
                try await metric.update(newValues)
                guard let newStartDate = newValues.last?.timestamp else {
                    // No more new values to add
                    return true
                }
                guard newStartDate > startDate else {
                    // No new values added
                    return true
                }
                startDate = newStartDate
                await observer.log("[\(metric.id)] Added \(newValues.count) values from remote")
            }
        } catch {
            await observer.log("Failed to update metric \(metric.id) from remote: \(error)")
            return false
        }
    }
}
