import Foundation
import Clairvoyant
import ClairvoyantClient
import Vapor

extension ServerRoute.Prefix {

    var path: [PathComponent] {
        switch self {
        case .getMetricList: return ["list"]
        case .lastValue: return ["last", hashParameter]
        case .allLastValues: return ["last", "all"]
        case .extendedInfoList: return ["list", "extended"]
        case .metricHistory: return ["history", hashParameter]
        case .pushValueToMetric: return ["push", hashParameter]
        }
    }

    var hashParameter: PathComponent {
        .parameter(ServerRoute.Prefix.hashParameterName)
    }

    public static let hashParameterName = "hash"

}

extension ServerRoute {

    func metricIdHash() throws -> MetricIdHash {
        switch self {
        case .lastValue(let hash), .metricHistory(let hash), .pushValueToMetric(let hash):
            return hash
        default:
            throw Abort(.badRequest)
        }
    }
}
