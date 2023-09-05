import Foundation
import Vapor
import Clairvoyant

public protocol MetricRequestAccessManager {

    func getAllowedMetrics(for request: Request, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}
