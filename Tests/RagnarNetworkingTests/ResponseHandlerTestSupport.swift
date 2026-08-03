import Foundation
@testable import RagnarNetworking

extension Interface {

    static func handleResponse(
        _ response: (data: Data, response: URLResponse),
        context: ResponseContext,
        handler: any ResponseHandler
    ) throws(ResponseError) -> Response {
        try handler.handle(
            response,
            for: Self.self,
            context: context
        )
    }

}
