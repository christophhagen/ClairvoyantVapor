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

    func getAccessibleMetric(_ request: Request, route: ServerRoute) throws -> GenericMetric {
        let metricIdHash = try request.metricIdHash()
        let metric = try observer.getMetricByHash(metricIdHash)
        let fullRoute = route.with(hash: metricIdHash)
        try accessManager.metricAccess(isAllowedForRequest: request, route: fullRoute)
        return metric
    }

    private func getDataOfRecordedMetricsList() throws -> Data {
        let list = observer.getListOfRecordedMetrics()
        return try encode(list)
    }

    private func getDataOfLastValuesForAllMetrics() async throws -> Data {
        let values = await observer.getLastValuesOfAllMetrics()
        return try encode(values)
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
        registerMetricListRoute(app, subPath: subPath)
        registerLastValueCollectionRoute(app, subPath: subPath)
        registerLastValueRoute(app, subPath: subPath)
        registerHistoryRoute(app, subPath: subPath)
        registerRemotePushRoute(app, subPath: subPath)
    }

    /**
     The route to access the list of registered metrics.

     - Type: `POST`
     - Path: `/metrics/list`
     - Headers:
        - `token` : The access token for the client
     - Response: `[MetricDescription]`
     */
    func registerMetricListRoute(_ app: Application, subPath: String) {
        app.post(subPath, route: .getMetricList) { [weak self] request async throws in
            guard let self else {
                throw Abort(.internalServerError)
            }

            try self.accessManager.metricAccess(isAllowedForRequest: request, route: .getMetricList)
            return try self.getDataOfRecordedMetricsList()
        }
    }

    /**
     The route to access the last values of all metrics.

     - Type: `POST`
     - Path: `/metrics/last/all`
     - Headers:
        - `token` : The access token for the client
     - Response: `[String : Data]`, a mapping between ID hash and encoded timestamped value.
     */
    func registerLastValueCollectionRoute(_ app: Application, subPath: String) {
        app.post(subPath, route: .allLastValues) { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            try self.accessManager.metricAccess(isAllowedForRequest: request, route: .allLastValues)
            return try await self.getDataOfLastValuesForAllMetrics()
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
    func registerLastValueRoute(_ app: Application, subPath: String) {
        app.post(subPath, route: .lastValue("")) { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request, route: .lastValue(""))
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
    func registerHistoryRoute(_ app: Application, subPath: String) {
        app.post(subPath, route: .metricHistory("")) { [weak self] request -> Data in
            guard let self else {
                throw Abort(.internalServerError)
            }
            let metric = try self.getAccessibleMetric(request, route: .metricHistory(""))
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
    func registerRemotePushRoute(_ app: Application, subPath: String) {
        app.post(subPath, route: .pushValueToMetric("")) { [weak self] request -> Data in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request, route: .pushValueToMetric(""))
            guard metric.canBeUpdatedByRemote else {
                throw Abort(.expectationFailed)
            }

            // Save value for metric
            let valueData = try request.body.bodyData.unwrap(or: Abort(.badRequest))
            try await metric.addDataFromRemote(valueData)
            return Data()
        }
    }
}
