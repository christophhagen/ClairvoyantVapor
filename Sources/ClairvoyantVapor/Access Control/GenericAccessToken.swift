import Foundation
import Clairvoyant

public protocol GenericAccessToken: TokenAccessManager, Hashable {

    var token: String { get }

    /**
     Check if the token allows access for the request
     - Parameter route: The route for which access is requested.
     - Parameter metrics: The metrics to be accessed with the request.
     - Throws: `MetricError.accessDenied`
     */
    func getAllowedMetrics(on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}

extension GenericAccessToken {

    public func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard accessToken == token else {
            // Only the single token is allowed
            throw MetricError.accessDenied
        }
        return try getAllowedMetrics(on: route, accessing: metrics)
    }
}
