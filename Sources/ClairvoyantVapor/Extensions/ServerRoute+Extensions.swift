import Foundation
import Clairvoyant
import Vapor

extension ServerRoute {

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

    func with(hash: MetricIdHash) -> ServerRoute {
        switch self {
        case .lastValue: return .lastValue(hash)
        case .metricHistory: return .metricHistory(hash)
        case .pushValueToMetric: return .pushValueToMetric(hash)
        default:
            return self
        }
    }

    func metricIdHash() throws -> MetricIdHash {
        switch self {
        case .lastValue(let hash), .metricHistory(let hash), .pushValueToMetric(let hash):
            return hash
        default:
            throw Abort(.badRequest)
        }
    }

    var hashParameter: PathComponent {
        .parameter(ServerRoute.hashParameterName)
    }

    public static let hashParameterName = "hash"


}
