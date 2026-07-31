//
//  ServerConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// How a server is spoken to: where it lives, how bodies are encoded and decoded, and
/// which headers every request carries.
///
/// This value is pure policy and is stable for a client's lifetime. Credentials are *not*
/// part of it - a per-request token travels in `RequestContext` alongside a configuration,
/// so a configuration can be shared freely without carrying a volatile secret.
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

    /// Creates a server configuration.
    /// - Parameters:
    ///   - url: The base URL for the API server
    ///   - requestEncoder: Encoder configuration for request bodies
    ///   - responseDecoder: Decoder configuration for response bodies
    ///   - defaultHeaders: Headers applied to every request; per-request `headers` take precedence
    public init(
        url: URL,
        requestEncoder: RequestEncoder = RequestEncoder(),
        responseDecoder: ResponseDecoder = ResponseDecoder(),
        defaultHeaders: [String: String] = [:]
    ) {
        self.url = url
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
        self.defaultHeaders = defaultHeaders
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
