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
        }
    }

    var hashParameter: PathComponent {
        .parameter(ServerRoute.hashParameterName)
    }

    public static let hashParameterName = "hash"


}
