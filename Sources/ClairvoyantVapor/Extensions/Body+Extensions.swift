import Foundation
import Vapor

extension Request.Body {

    var bodyData: Data? {
        data?.all()
    }
}
