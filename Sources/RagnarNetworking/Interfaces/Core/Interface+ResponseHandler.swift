//
//  Interface+ResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

// MARK: - Response Handling

public extension Interface {

    /// Interfaces use the configured handler unless they override this.
    static var responseHandler: (any ResponseHandler)? { nil }

    /// Processes a raw HTTP response according to the Interface's response contract.
    ///
    /// This method validates the response type, checks the status code against the Interface's
    /// response contract, and either decodes a success response or throws the appropriate error.
    ///
    /// Both configuration arguments are required rather than defaulted, so a caller cannot
    /// silently fall back to a plain `JSONDecoder` or `DefaultResponseHandler` and lose the
    /// client's rules.
    ///
    /// - Parameters:
    ///   - response: Tuple containing the response data and URLResponse
    ///   - context: The configuration this response is handled under. Normally
    ///     `ServerConfiguration.responseContext`.
    ///   - defaultHandler: Used when the Interface does not override `responseHandler`.
    ///     Normally `ServerConfiguration.responseHandler`.
    /// - Returns: The decoded Response type
    /// - Throws: `ResponseError` if the response cannot be processed
    static func handle(
        _ response: (data: Data, response: URLResponse),
        context: ResponseContext,
        defaultHandler: any ResponseHandler
    ) throws(ResponseError) -> Response {
        let handler = responseHandler ?? defaultHandler

        return try handler.handle(
            response,
            for: Self.self,
            context: context
        )
    }

}
