import Foundation
import Clairvoyant
import ClairvoyantClient
import Vapor

public struct ScopedAccessToken {

    /**
     The function that can be accessed with a scoped token
     */
    public enum Scope: String {
        case list
        case last
        case history
        case push
    }

    /// The string access token (a base64 encoded string)
    public let token: String

    /**
     The routes permitted to access.

     For routes to a specific metric, the metric must allowed via `allowedMetrics` and `deniedMetrics`
     */
    public let permissions: Set<Scope>

    /**
     The specific metrics to allow.

     If this set is empty, then all metrics except the `forbiddenMetrics` are allowed.
     */
    public let accessibleMetricsHashes: Set<MetricIdHash>

    private let accessibleMetrics: Set<MetricId>

    /**
     The specific metrics not accessible by the token.
     */
    public let inaccessibleMetricsHashes: Set<MetricIdHash>

    private let inaccessibleMetrics: Set<MetricId>

    public init(token: String, permissions: Set<Scope>, accessibleMetrics: any Sequence<MetricId> = [], inaccessibleMetrics: any Sequence<MetricId> = []) {
        self.token = token
        self.permissions = permissions

        let inaccessible = Set(inaccessibleMetrics)
        let inaccessibleHashes = inaccessibleMetrics.map { $0.hashed() }
        let accessible = Set(accessibleMetrics)
        let accessibleHashes = accessibleMetrics.map { $0.hashed() }

        self.accessibleMetrics = accessible
        self.accessibleMetricsHashes = Set(accessibleHashes)
            .subtracting(inaccessibleHashes)
        self.inaccessibleMetrics = inaccessible
        self.inaccessibleMetricsHashes = Set(inaccessibleHashes)
    }

    func allowsAccess(for metricHash: MetricIdHash) -> Bool {
        if accessibleMetricsHashes.isEmpty {
            // All metrics are allowed, unless explicitly specified
            return !inaccessibleMetricsHashes.contains(metricHash)
        } else {
            // Only accessible metrics are allowed
            return accessibleMetricsHashes.contains(metricHash)
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

extension ScopedAccessToken: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(accessibleMetrics, forKey: .accessibleMetrics)
        try container.encode(inaccessibleMetrics, forKey: .inaccessibleMetrics)
    }

    enum CodingKeys: String, CodingKey {
        case token = "token"
        case permissions
        case accessibleMetrics
        case inaccessibleMetrics
    }
}

extension ScopedAccessToken: Decodable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let token = try container.decode(String.self, forKey: .token)
        let permissions = try container.decode(Set<Scope>.self, forKey: .permissions)
        let accessibleMetrics = try container.decode(Set<MetricId>.self, forKey: .accessibleMetrics)
        let inaccessibleMetrics = try container.decode(Set<MetricId>.self, forKey: .inaccessibleMetrics)
        self.init(
            token: token,
            permissions: permissions,
            accessibleMetrics: accessibleMetrics,
            inaccessibleMetrics: inaccessibleMetrics)
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

