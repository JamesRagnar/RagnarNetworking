//
//  ResponseContext.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// What a `ResponseHandler` needs from the configuration to handle one response.
///
/// The response-side peer of `RequestContext`, kept separate so a response handler never holds
/// the request's credential.
///
/// A new member belongs here if handling a response requires it. Anything a handler needs for
/// one endpoint only belongs on that Interface.
public struct ResponseContext: Sendable {

    /// Decoder configuration for response bodies. Implementations should use it for every body
    /// they decode, including typed error bodies, so a client's decoding rules apply uniformly.
    public let responseDecoder: ResponseDecoder

    /// Query item names to strip from the URL captured in `HTTPResponseSnapshot`, so a
    /// URL-carried credential does not reach a logged error.
    ///
    /// Unioned from `ServerConfiguration.authenticators`.
    public let redactedQueryItemNames: Set<String>

    /// Creates a response context.
    /// - Parameters:
    ///   - responseDecoder: Decoder configuration for response bodies
    ///   - redactedQueryItemNames: Query item names to strip from captured response URLs.
    ///     Normally `ServerConfiguration.redactedQueryItemNames`.
    public init(
        responseDecoder: ResponseDecoder,
        redactedQueryItemNames: Set<String> = []
    ) {
        self.responseDecoder = responseDecoder
        self.redactedQueryItemNames = redactedQueryItemNames
    }

}
