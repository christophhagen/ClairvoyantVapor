import Foundation
import Clairvoyant

extension MetricAccessToken: MetricAccessManager {

    public func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard accessToken == base64 else {
            // Only the single token is allowed
            throw MetricError.accessDenied
        }
        return metrics
    }
}

extension MetricAccessToken: GenericAccessToken {

    public func getAllowedMetrics(on route: ServerRoute, accessing metrics: [MetricIdHash]) -> [MetricIdHash] {
        return metrics
    }
}
