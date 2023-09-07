import Foundation
import Clairvoyant
import ClairvoyantClient

extension String: GenericAccessToken {

    public var token: String {
        self
    }

    public func getAllowedMetrics(on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        // Allow all scopes and metrics
        metrics
    }
}
