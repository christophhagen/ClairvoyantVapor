import Foundation
import Clairvoyant
import Vapor

public struct ScopedAccessToken {

    public enum Scope: String {
        case list
        case last
        case history
        case push
    }

    public let base64: String

    /**
     The routes permitted to access.

     For routes to a specific metric, the metric must allowed via `allowedMetrics` and `deniedMetrics`
     */
    public let permissions: Set<Scope>

    /**
     The specific metrics to allow.

     If this set is empty, then all metrics except the `forbiddenMetrics` are allowed.
     */
    public let accessibleMetrics: Set<MetricIdHash>

    /**
     The specific metrics not accessible by the token.
     */
    public let inaccessibleMetrics: Set<MetricIdHash>

    public init(base64: String, permissions: Set<Scope>, accessibleMetrics: any Sequence<MetricId>, inaccessibleMetrics: any Sequence<MetricId>) {
        self.base64 = base64
        self.permissions = permissions
        let inaccessible = Set(inaccessibleMetrics.map { $0.hashed() })
        self.accessibleMetrics = Set(accessibleMetrics.map { $0.hashed() })
            .subtracting(inaccessible)
        self.inaccessibleMetrics = inaccessible
    }

    func allowsAccess(for metricHash: MetricIdHash) -> Bool {
        if accessibleMetrics.isEmpty {
            // All metrics are allowed, unless explicitly specified
            return !inaccessibleMetrics.contains(metricHash)
        } else {
            // Only accessible metrics are allowed
            return accessibleMetrics.contains(metricHash)
        }
    }

    /**

     */
    func hasPermission(toAccess route: ServerRoute) -> Bool {
        switch route {
        case .getMetricList:
            return permissions.contains(.list)
        case .lastValue(let metricIdHash):
            return permissions.contains(.last) && allowsAccess(for: metricIdHash)
        case .allLastValues, .extendedInfoList:
            return permissions.contains(.last) && permissions.contains(.list)
        case .metricHistory(let metricIdHash):
            return permissions.contains(.history) && allowsAccess(for: metricIdHash)
        case .pushValueToMetric(let metricIdHash):
            return permissions.contains(.push) && allowsAccess(for: metricIdHash)
        }
    }
}

extension ScopedAccessToken.Scope: Codable {

}

extension ScopedAccessToken.Scope: Equatable {

}

extension ScopedAccessToken.Scope: Hashable {

}

extension ScopedAccessToken: Hashable {

}

extension ScopedAccessToken: Codable {

}

extension ScopedAccessToken: MetricAccessManager {

    public func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard accessToken == base64 else {
            // Only the single token is allowed
            throw MetricError.accessDenied
        }
        return try getAllowedMetrics(on: route, accessing: metrics)
    }
}

extension ScopedAccessToken: GenericAccessToken {

    public func getAllowedMetrics(on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard hasPermission(toAccess: route) else {
            throw MetricError.accessDenied
        }
        return metrics.filter(allowsAccess)
    }
}

