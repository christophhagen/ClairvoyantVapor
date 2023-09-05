import Foundation
import Clairvoyant

public protocol GenericAccessToken: Hashable {

    var base64: String { get }

    /**
     Check if the token allows access for the request
     - Parameter route: The route for which access is requested.
     - Parameter metrics: The metrics to be accessed with the request.
     - Throws: `MetricError.accessDenied`
     */
    func getAllowedMetrics(on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}
