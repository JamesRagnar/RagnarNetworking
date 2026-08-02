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

    /// Gives each `AuthenticationScheme` its meaning for this server: which header fields and
    /// query items carry the credential for it.
    ///
    /// A request declaring no scheme never consults this.
    public let authenticators: [AuthenticationScheme: any Authenticator]

    /// Decides which failed responses mean the credential is stale.
    ///
    /// Defaults to `.unmodelled401`, which refreshes on 401 unless the Interface declared an
    /// exact `.code(401, ...)` case. Use `.any401` to refresh on every 401.
    public let challengePolicy: AuthenticationChallengePolicy

    /// Query item names stripped from the URL captured in `HTTPResponseSnapshot`.
    ///
    /// The union of `authenticators`' own `redactedQueryItemNames`, computed at init. Request
    /// construction rejects an authenticator that writes a name outside its own declaration, so
    /// this cannot fall out of step with what is written.
    public let redactedQueryItemNames: Set<String>

    /// Creates a server configuration.
    /// - Parameters:
    ///   - url: The base URL for the API server
    ///   - requestEncoder: Encoder configuration for request bodies
    ///   - responseDecoder: Decoder configuration for response bodies
    ///   - defaultHeaders: Headers applied to every request; per-request `headers` take precedence
    ///   - builder: Builds requests from Interface parameters. Defaults to `URLRequestBuilder()`.
    ///   - responseHandler: Handles responses for Interfaces that do not override their own.
    ///     Defaults to `DefaultResponseHandler()`.
    ///   - authenticators: Gives each `AuthenticationScheme` its meaning. Defaults to
    ///     `.bearer` writing `Authorization: Bearer <credential>` and `.url` writing
    ///     `?token=<credential>`.
    ///   - challengePolicy: Which failures mean the credential is stale. Defaults to
    ///     `.unmodelled401`.
    public init(
        url: URL,
        requestEncoder: RequestEncoder = RequestEncoder(),
        responseDecoder: ResponseDecoder = ResponseDecoder(),
        defaultHeaders: [String: String] = [:],
        builder: any RequestBuilder = URLRequestBuilder(),
        responseHandler: any ResponseHandler = DefaultResponseHandler(),
        authenticators: [AuthenticationScheme: any Authenticator] = [
            .bearer: .bearer,
            .url: .token
        ],
        challengePolicy: AuthenticationChallengePolicy = .unmodelled401
    ) {
        self.url = url
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
        self.defaultHeaders = defaultHeaders
        self.builder = builder
        self.responseHandler = responseHandler
        self.authenticators = authenticators
        self.challengePolicy = challengePolicy
        self.redactedQueryItemNames = authenticators.values.reduce(into: Set<String>()) {
            $0.formUnion($1.redactedQueryItemNames)
        }
    }

    /// The authenticator registered for `scheme`.
    ///
    /// - Throws: `RequestError.unregisteredScheme` when nothing is registered for it.
    public func authenticator(
        for scheme: AuthenticationScheme
    ) throws(RequestError) -> any Authenticator {
        guard let authenticator = authenticators[scheme] else {
            throw .unregisteredScheme(scheme)
        }

        return authenticator
    }

    /// Configuration for handling a response from this server.
    public var responseContext: ResponseContext {
        ResponseContext(
            responseDecoder: responseDecoder,
            redactedQueryItemNames: redactedQueryItemNames
        )
    }

    /// The headers a request should be built with: `defaultHeaders` overlaid with the
    /// request's own `headers`.
    ///
    /// Matching is case-insensitive, so a default `content-type` and a request
    /// `Content-Type` resolve to a single header with the request's value rather than
    /// two entries whose winner is unspecified.
    ///
    /// Resolution lives here rather than inside the request-building pipeline so no
    /// `RequestBuilder` can drop `defaultHeaders`, including one that replaces `buildRequest`
    /// wholesale.
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
