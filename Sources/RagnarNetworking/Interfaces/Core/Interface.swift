//
//  Interface.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// Defines the contract for a network request endpoint, including its parameters,
/// response type, and status code handling.
///
/// Conform to this protocol to create type-safe API endpoint definitions. The protocol connects
/// request parameters with their expected response types and defines how different HTTP status
/// codes should be interpreted.
public protocol Interface: Sendable {

    /// The request shape defining how to construct the network request
    associatedtype Request: InterfaceRequest

    /// The expected response type when the request succeeds.
    ///
    /// A `Decodable` type conforms to `InterfaceResponse` without implementing anything and
    /// decodes as JSON. `String`, `Data`, and `EmptyResponse` carry built-in conformances.
    associatedtype Response: InterfaceResponse & Sendable

    /// Defines which status codes produce `Response` and which produce declared failures.
    ///
    /// The generic binding makes the successful status contract inseparable from the declared
    /// `Response` type. Every contract requires at least one successful status matcher.
    static var responses: ResponseContract<Response> { get }

}

// MARK: - Interface Request

/// Defines the components needed to construct an HTTP request.
///
/// Implement this protocol to specify all the details of your network request, including
/// the HTTP method, path, query parameters, headers, body, and authentication requirements.
/// This protocol is typically implemented as a nested type within an `Interface` conformance.
public protocol InterfaceRequest: Sendable {

    /// The HTTP method for this request (GET, POST, etc.)
    var method: RequestMethod { get }

    /// The path component of the URL (e.g., "/api/users/123")
    var path: String { get }

    /// Optional ordered query parameters to append to the URL.
    var queryItems: [URLQueryItem]? { get }

    /// Optional HTTP headers to include in the request
    var headers: [String: String]? { get }

    /// The concrete body type for this request.
    /// Defaults to `EmptyBody` for requests without a body.
    associatedtype Body: RequestBody = EmptyBody

    /// The request body for this request.
    ///
    /// Use `EmptyBody()` for requests without a body.
    var body: Body { get }

    /// The authentication scheme for this request, or `nil` if it carries no credential.
    ///
    /// Names a strategy; `ServerConfiguration.authenticators` decides what that name means for
    /// this server.
    var authentication: AuthenticationScheme? { get }

    /// Whether this request allows the client's credential source to refresh after a challenge.
    ///
    /// Independent of whether a credential is applied, which follows `authentication` alone.
    /// Defaults to `authentication != nil`.
    ///
    /// Override to `true` for a credential this package does not apply, such as one held in a
    /// cookie jar or added by a signing `Transport`; the request otherwise gets no retry and no
    /// refresh. Override to `false` for an endpoint that must not refresh, such as the
    /// token-refresh endpoint itself, where a challenge has to surface to the caller.
    /// A read-only `CredentialSource` always surfaces the challenge without retrying.
    var allowsRefreshOnChallenge: Bool { get }

}

public extension InterfaceRequest {

    var allowsRefreshOnChallenge: Bool {
        authentication != nil
    }

}

// MARK: Request Method

/// Standard HTTP request methods.
public enum RequestMethod: String, Sendable {

    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case head = "HEAD"
    case delete = "DELETE"
    case patch = "PATCH"
    case options = "OPTIONS"
    case connect = "CONNECT"
    case trace = "TRACE"

}
