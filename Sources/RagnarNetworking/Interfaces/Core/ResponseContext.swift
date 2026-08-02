//
//  ResponseContext.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// What a `ResponseHandler` needs from the configuration to handle one response.
///
/// The response-side peer of `RequestContext`, and deliberately a separate type: a response
/// handler has no business holding the request's credential.
///
/// A new member belongs here if handling a response requires it. Anything a handler only needs
/// for one endpoint belongs on that Interface instead.
public struct ResponseContext: Sendable {

    /// Decoder configuration for response bodies. Implementations should use it for every body
    /// they decode, including typed error bodies, so a client's decoding rules apply uniformly.
    public let responseDecoder: ResponseDecoder

    /// Query item names to strip from the URL captured in `HTTPResponseSnapshot`.
    ///
    /// Unioned from `ServerConfiguration.authenticators`, so a credential carried in a URL does
    /// not survive into an error a consumer logs or attaches to a bug report.
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
