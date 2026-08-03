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
    ///   - context: The decoder to use for every body, including typed error bodies, and the
    ///     query item names to strip from any `HTTPResponseSnapshot` the handler captures.
    ///
    /// - Important: Surface a status code the Interface's `responseCases` does not match as
    ///   `ResponseError.unknownResponseCase`. Consumers, including
    ///   `AuthenticationChallengePolicy`, distinguish it from a mapped failure.
    func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        context: ResponseContext
    ) throws(ResponseError) -> T.Response

}
