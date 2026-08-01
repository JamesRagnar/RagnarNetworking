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

    /// Processes a raw HTTP response according to the Interface's response cases.
    ///
    /// This method validates the response type, checks the status code against the Interface's
    /// defined response cases, and either decodes a success response or throws the appropriate error.
    ///
    /// - Parameters:
    ///   - response: Tuple containing the response data and URLResponse
    ///   - responseDecoder: Decoder to use when decoding the response body, normally the
    ///     client's configured `ServerConfiguration.responseDecoder`. Required rather than
    ///     defaulted, so a caller cannot silently fall back to a plain `JSONDecoder` and lose
    ///     the client's decoding rules.
    ///   - defaultHandler: The handler to use when the Interface does not override
    ///     `responseHandler`, normally the client's configured
    ///     `ServerConfiguration.responseHandler`.
    /// - Returns: The decoded Response type
    /// - Throws: `ResponseError` if the response cannot be processed
    static func handle(
        _ response: (data: Data, response: URLResponse),
        responseDecoder: ResponseDecoder,
        defaultHandler: any ResponseHandler = DefaultResponseHandler()
    ) throws(ResponseError) -> Response {
        let handler = responseHandler ?? defaultHandler

        return try handler.handle(
            response,
            for: Self.self,
            responseDecoder: responseDecoder
        )
    }

}
