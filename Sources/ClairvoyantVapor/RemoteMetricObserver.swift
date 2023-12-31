import Foundation
import ClairvoyantClient

public struct RemoteMetricObserver {

    /**
     The url of the remote server.

     The url only contains the common part of the metrics API,
     e.g. the url where the Vapor instance is running,
     plus the subPath passed to `registerRoutes(_:subPath:)` on the remote server.
     */
    public let remoteUrl: URL

    /// The provider of the authentication required to access the remote server
    let accessProvider: RequestAccessProvider

    public init(remoteUrl: URL, accessProvider: RequestAccessProvider) {
        self.remoteUrl = remoteUrl
        self.accessProvider = accessProvider
    }
}

extension RemoteMetricObserver: Equatable {

    public static func == (lhs: RemoteMetricObserver, rhs: RemoteMetricObserver) -> Bool {
        lhs.remoteUrl == rhs.remoteUrl
    }
}

extension RemoteMetricObserver: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(remoteUrl)
    }
}
