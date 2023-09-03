import Foundation
import Vapor
import Clairvoyant

extension Application {

    @discardableResult
    func post(_ subPath: String, route: ServerRoute, use closure: @escaping (Request) async throws -> Data) -> Route {
        post([.constant(subPath)] + route.path)  { request -> Response in
            do {
                let data = try await closure(request)
                return .init(status: .ok, body: .init(data: data))
            } catch let error as MetricError {
                return Response(status: error.status)
            } catch {
                throw error
            }
        }
    }
}
