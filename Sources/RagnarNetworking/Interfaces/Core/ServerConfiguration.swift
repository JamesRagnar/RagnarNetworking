//
//  ServerConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// How a server is spoken to: where it lives, how bodies are encoded and decoded, which
/// headers every request carries, and how requests and responses are shaped.
///
/// This value is pure policy and is stable for a client's lifetime. Two things are
/// deliberately *not* part of it:
///
/// - **Credentials.** A per-request token travels in `RequestContext` alongside a
///   configuration, so a configuration can be shared freely without carrying a volatile secret.
/// - **The `Transport`.** A transport answers "what process are we in?" (a live `URLSession`, a
///   mock, a recorded fixture) rather than "which server is this?", so it belongs to
///   `RequestPipeline` and stays available as the test seam.
///
/// Everything else that describes the server belongs here. That is the rule for deciding where
/// a new knob goes.
public struct ServerConfiguration: Sendable {

    /// The base URL for all API requests (e.g., "https://api.example.com")
    public let url: URL

    /// Encoder configuration for request bodies. Uses a factory pattern
    /// to maintain Sendable conformance in Swift 6.
    public let requestEncoder: RequestEncoder

    /// Decoder configuration for response bodies. Uses a factory pattern
    /// to maintain Sendable conformance in Swift 6.
    public let responseDecoder: ResponseDecoder

    /// Headers applied to every request built from this configuration.
    /// A header with the same name in a request's own `headers` takes precedence,
    /// matched case-insensitively per HTTP semantics.
    public let defaultHeaders: [String: String]

    /// Builds `URLRequest` values from Interface parameters for this server.
    ///
    /// Path joining, header conventions, and request signing are all part of a server's
    /// contract, so the builder lives with the rest of that contract rather than being passed
    /// alongside the transport.
    public let builder: any RequestBuilder

    /// Handles responses for Interfaces that do not override `Interface.responseHandler`.
    ///
    /// Set this for a concern that applies across the whole API - unwrapping a `{ "data": ... }`
    /// envelope, reading a deprecation header, feeding a metrics sink - so it is written once
    /// instead of on every Interface.
    public let responseHandler: any ResponseHandler

    /// Creates a server configuration.
    /// - Parameters:
    ///   - url: The base URL for the API server
    ///   - requestEncoder: Encoder configuration for request bodies
    ///   - responseDecoder: Decoder configuration for response bodies
    ///   - defaultHeaders: Headers applied to every request; per-request `headers` take precedence
    ///   - builder: Builds requests from Interface parameters. Defaults to `URLRequestBuilder()`.
    ///   - responseHandler: Handles responses for Interfaces that do not override their own.
    ///     Defaults to `DefaultResponseHandler()`.
    public init(
        url: URL,
        requestEncoder: RequestEncoder = RequestEncoder(),
        responseDecoder: ResponseDecoder = ResponseDecoder(),
        defaultHeaders: [String: String] = [:],
        builder: any RequestBuilder = URLRequestBuilder(),
        responseHandler: any ResponseHandler = DefaultResponseHandler()
    ) {
        self.url = url
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
        self.defaultHeaders = defaultHeaders
        self.builder = builder
        self.responseHandler = responseHandler
    }

    /// The headers a request should be built with: `defaultHeaders` overlaid with the
    /// request's own `headers`.
    ///
    /// Matching is case-insensitive, so a default `content-type` and a request
    /// `Content-Type` resolve to a single header with the request's value rather than
    /// two entries whose winner is unspecified.
    ///
    /// Resolution lives here rather than inside the request-building pipeline so no
    /// `RequestBuilder` can drop `defaultHeaders` by overriding a pipeline step.
    public func resolvedHeaders(for parameters: some RequestParameters) -> [String: String] {
        resolvedHeaders(overriddenBy: parameters.headers)
    }

    /// `defaultHeaders` overlaid with `headers`, matched case-insensitively.
    public func resolvedHeaders(overriddenBy headers: [String: String]?) -> [String: String] {
        guard let headers, !headers.isEmpty else {
            return defaultHeaders
        }

        var resolved = defaultHeaders
        for (name, value) in headers {
            resolved = resolved.filter {
                $0.key.caseInsensitiveCompare(name) != .orderedSame
            }
            resolved[name] = value
        }

        return resolved
    }

}
