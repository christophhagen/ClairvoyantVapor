import Foundation
import Clairvoyant

/**
A very simple access control manager to protect observed metrics.

 Some form of access manager is required for each metric observer.
 ```
 let manager = AccessTokenManager(...)
 let observer = MetricObserver(logFolder: ..., accessManager: manager, logMetricId: ...)
 ```
 */
public final class AccessTokenManager<Token> where Token: GenericAccessToken {

    private var tokens: Set<Token>

    /**
     Create a new manager with a set of access tokens.
     - Parameter tokens: The access tokens which should have access to the metrics
     */
    public init<T>(_ tokens: T) where T: Sequence<Token> {
        self.tokens = Set(tokens)
    }

    /**
     Add a new access token.
     - Parameter token: The access token to add.
     */
    public func add(_ token: Token) {
        tokens.insert(token)
    }

    /**
     Remove an access token.
     - Parameter token: The access token to remove.
     */
    public func remove(_ token: Token) {
        tokens.remove(token)
    }

    public func getToken(for id: String) -> Token? {
        tokens.first { $0.base64 == id }
    }

}

extension AccessTokenManager: MetricAccessManager {

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter accessToken: The access token provided in the request.
     - Throws: `MetricError.accessDenied`
     */
    public func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard let token = getToken(for: accessToken) else {
            throw MetricError.accessDenied
        }
        return try token.getAllowedMetrics(on: route, accessing: metrics)
    }
}
