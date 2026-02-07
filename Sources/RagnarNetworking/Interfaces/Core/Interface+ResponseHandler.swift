//
//  Interface+ResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

// MARK: - Response Handling

public extension Interface {

    /// Default response handler for Interfaces.
    static var responseHandler: ResponseHandler.Type {
        DefaultResponseHandler.self
    }

    /// Processes a raw HTTP response according to the Interface's response cases.
    ///
    /// This method validates the response type, checks the status code against the Interface's
    /// defined response cases, and either decodes a success response or throws the appropriate error.
    ///
    /// - Parameter response: Tuple containing the response data and URLResponse
    /// - Returns: The decoded Response type
    /// - Throws: `ResponseError` if the response cannot be processed
    static func handle(
        _ response: (data: Data, response: URLResponse)
    ) throws(ResponseError) -> Response {
        return try responseHandler.handle(response, for: Self.self)
    }

}
