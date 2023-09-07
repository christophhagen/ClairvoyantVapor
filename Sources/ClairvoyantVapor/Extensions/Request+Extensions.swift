import Foundation
import Clairvoyant
import ClairvoyantClient
import Vapor

extension Request {

    func token() throws -> String {
        guard let string = headers.first(name: ServerRoute.headerAccessToken) else {
            throw Abort(.badRequest)
        }
        return string
    }

    var bodyData: Data? {
        body.data?.all()
    }

    func decodeBody<T>(as type: T.Type = T.self, using decoder: BinaryDecoder) throws -> T where T: Decodable {
        guard let data = bodyData else {
            throw Abort(.badRequest)
        }
        do {
            return try decoder.decode(from: data)
        } catch {
            throw Abort(.badRequest)
        }
    }

    func metricIdHash() throws -> MetricIdHash {
        guard let metricIdHash = parameters.get(ServerRoute.Prefix.hashParameterName, as: String.self) else {
            throw Abort(.badRequest)
        }
        return metricIdHash
    }
}
