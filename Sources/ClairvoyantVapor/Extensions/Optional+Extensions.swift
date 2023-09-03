import Foundation

extension Optional {

    func unwrap(or error: Error) throws -> Wrapped {
        guard let wrapped else {
            throw error
        }
        return wrapped
    }
}
