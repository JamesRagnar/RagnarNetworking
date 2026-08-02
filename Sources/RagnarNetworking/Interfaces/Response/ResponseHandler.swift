//
//  ResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Handles decoding and mapping of responses for an Interface.
///
/// Handlers are values rather than metatypes, so a handler may carry its own state - a
/// metrics sink, a header allowlist - without reaching for globals.
public protocol ResponseHandler: Sendable {

    /// Handle a response for a given Interface type.
    ///
    /// - Parameters:
    ///   - response: Tuple containing the response data and URLResponse
    ///   - interface: The interface type defining the response contract
    ///   - context: The configuration this response is handled under: the decoder to use for
    ///     every body, including typed error bodies, and the query item names to strip from any
    ///     `HTTPResponseSnapshot` the handler captures.
    ///
    /// - Important: A status code the Interface's `responseCases` does not match should be
    ///   surfaced as `ResponseError.unknownResponseCase`. Consumers distinguish "the endpoint
    ///   declared nothing for this code" from a mapped failure, and a handler that collapses
    ///   the two takes that away.
    func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        context: ResponseContext
    ) throws(ResponseError) -> T.Response

}

// MARK: - Response Outcome Result

/// The result of a handled response, allowing non-decoding success cases.
///
/// Returned by `DefaultResponseHandler.handleOutcome`, for custom `ResponseHandler`
/// implementations that compose with it rather than reimplementing status-code matching.
public enum ResponseOutcomeResult<Response: Sendable>: Sendable {

    /// The response was decoded as the Interface's Response type.
    case decoded(Response)

    /// The response was a success with no body (e.g., 204/205/304).
    case noContent

}
