import Foundation
import Vapor
import Clairvoyant

/**
 A protocol that can be implemented to control access to metrics via binary access tokens.

 Using a `MetricAccessManager` over a `MetricRequestAccessManager` requires the
 existence of a "`token`" header in each request containing the access token as base64 encoded data.

 On the client side, the `MetricAccessTokenProvider` protocol can be used to ensure compatibility.

 First, implement your own version of access control.

 ```
 struct MyAccessTokenManager: MetricAccessManager {

    func metricListAccess(isAllowedForToken accessToken: MetricAccessToken) throws {
        ...
    }

    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: MetricAccessToken) throws {
        ...
    }
 }
 ```

 Then you can use the manager to protect access to metrics.

 ```
 let manager = MyAccessTokenManager(...)
 let observer = MetricObserver(logFolder: ..., accessManager: manager, logMetricId: ...)
 ```
 */
public protocol MetricAccessManager: MetricRequestAccessManager {

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter accessToken: The access token provided in the request.
     - Parameter route: The route for which access is requested.
     - Parameter metrics: The metrics to be accessed with the request.
     - Throws: `MetricError.accessDenied`
     */
    func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}

public extension MetricAccessManager {

    func getAllowedMetrics(for request: Request, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        let accessToken = try request.token()
        return try getAllowedMetrics(for: accessToken, on: route, accessing: metrics)
    }
}
