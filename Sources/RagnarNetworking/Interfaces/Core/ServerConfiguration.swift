//
//  ServerConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// A server's contract: where it lives, how bodies are encoded and decoded, which headers every
/// request carries, and how requests and responses are shaped. Stable for a client's lifetime.
///
/// Credentials are not part of it; a per-request token travels in `RequestContext`. Neither is
/// the `Transport`, which belongs to `RequestPipeline`.
///
/// A new knob belongs here if the server requires or guarantees it. Per-request mechanics the
/// server never sees, such as a timeout or a cache policy, do not.
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
    public let builder: any RequestBuilder

    /// Handles responses for Interfaces that do not override `Interface.responseHandler`.
    ///
    /// Use for concerns that apply across the whole API, such as unwrapping a
    /// `{ "data": ... }` envelope or reading a deprecation header.
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
