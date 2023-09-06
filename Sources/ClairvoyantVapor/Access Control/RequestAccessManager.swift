import Foundation
import Vapor
import Clairvoyant

public protocol RequestAccessManager {

    func getAllowedMetrics(for request: Request, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}
