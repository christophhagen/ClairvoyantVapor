import Foundation
import Clairvoyant
import ClairvoyantVapor

final class MyAuthenticator: TokenAccessManager {

    func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        return metrics
    }
}
