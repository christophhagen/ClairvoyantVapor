import Foundation
import Vapor
import Clairvoyant

/**
 A protocol that can be implemented to control access to metrics via access tokens.

 Using a `TokenAccessManager` over a `RequestAccessManager` requires the
 existence of a "`token`" header in each request containing the access token as a string.

 On the client side, the `MetricAccessTokenProvider` protocol can be used to ensure compatibility.
 */
public protocol TokenAccessManager: RequestAccessManager {

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter accessToken: The access token provided in the request.
     - Parameter route: The route for which access is requested.
     - Parameter metrics: The metrics to be accessed with the request.
     - Throws: `MetricError.accessDenied`
     */
    func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}

public extension TokenAccessManager {

    func getAllowedMetrics(for request: Request, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        let accessToken = try request.token()
        return try getAllowedMetrics(for: accessToken, on: route, accessing: metrics)
    }
}
