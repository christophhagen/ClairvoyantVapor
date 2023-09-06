import Foundation
import Clairvoyant
import Vapor

extension Set: RequestAccessManager where Element: GenericAccessToken {

}

extension Set: TokenAccessManager where Element: GenericAccessToken {

}

extension Array: RequestAccessManager where Element: GenericAccessToken {

}

extension Array: TokenAccessManager where Element: GenericAccessToken {

}

extension Sequence where Element: GenericAccessToken {

    public func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard let token = first(where: { $0.token == accessToken }) else {
            throw MetricError.accessDenied
        }
        return try token.getAllowedMetrics(on: route, accessing: metrics)
    }
}
