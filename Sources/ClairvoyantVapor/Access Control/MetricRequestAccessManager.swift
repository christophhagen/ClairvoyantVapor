import Foundation
import Vapor
import Clairvoyant

public protocol MetricRequestAccessManager {

    func metricAccess(isAllowedForRequest request: Request, route: ServerRoute) throws
}
