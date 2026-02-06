//
//  ResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Handles decoding and mapping of responses for an Interface.
public protocol ResponseHandler {

    /// Handle a response for a given Interface type.
    static func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> T.Response

}

// MARK: - Response Outcome Result

/// The result of a handled response, allowing non-decoding success cases.
public enum ResponseOutcomeResult<Response: Sendable>: Sendable {

    /// The response was decoded as the Interface's Response type.
    case decoded(Response)

    /// The response was a success with no body (e.g., 204/205/304).
    case noContent

}
