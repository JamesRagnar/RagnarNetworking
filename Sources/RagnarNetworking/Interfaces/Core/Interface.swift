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

    /// The parameters defining how to construct the network request
    associatedtype Parameters: RequestParameters

    /// The expected response type when the request succeeds.
    ///
    /// A `Decodable` type conforms to `InterfaceResponse` without implementing anything and
    /// decodes as JSON. `String`, `Data`, and `EmptyResponse` carry built-in conformances.
    associatedtype Response: InterfaceResponse & Sendable

    /// Defines how each HTTP status code should be handled for this interface.
    ///
    /// Declare this as a `static let`. A computed `static var` rebuilds the map on every
    /// response.
    static var responseCases: ResponseMap { get }

    /// Overrides response handling for this endpoint alone.
    ///
    /// `nil`, the default, uses `ServerConfiguration.responseHandler`. Return a handler for an
    /// endpoint whose response does not follow the rest of the API.
    ///
    /// An Interface-level handler *replaces* the configured one rather than layering on it. An
    /// endpoint that overrides in an API whose configuration unwraps an envelope has to unwrap
    /// that envelope itself.
    ///
    /// For decoding rules that differ only in field names or date format, use `CodingKeys`, a
    /// custom `init(from:)`, or an `InterfaceResponse` conformance on the `Response` type.
    ///
    /// - Warning: An override written as `static var responseHandler: any ResponseHandler`
    ///   compiles but does not satisfy this requirement, because property witness types are
    ///   invariant. It becomes dead and the endpoint silently uses the configured handler.
    ///   Swift emits no diagnostic. Overrides must return `(any ResponseHandler)?`.
    static var responseHandler: (any ResponseHandler)? { get }

}

// MARK: - Request Parameters

/// Defines the components needed to construct an HTTP request.
///
/// Implement this protocol to specify all the details of your network request, including
/// the HTTP method, path, query parameters, headers, body, and authentication requirements.
/// This protocol is typically implemented as a nested type within an `Interface` conformance.
public protocol RequestParameters: Sendable {

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

    /// Whether a challenge on this request should trigger a refresh and one retry.
    ///
    /// Independent of whether a credential is applied, which follows `authentication` alone.
    /// Defaults to `authentication != nil`; both overrides are meaningful:
    ///
    /// - `true` with no scheme, for a credential this package does not apply: a cookie jar, a
    ///   signing `Transport`, a proxy. Without it the request gets no retry and no refresh.
    /// - `false` with a scheme, for an endpoint that must not refresh. A token-refresh endpoint
    ///   sends a credential of its own, and a challenge on it has to surface rather than
    ///   recurse into another refresh.
    ///
    /// The only member here with a default implementation, because it is the only derived one.
    /// It is a requirement rather than an extension-only member so that an override reaches
    /// `APIClient`, which reads it through a generic constraint; an extension-only member
    /// would be dispatched statically there and the override would silently do nothing.
    var refreshesOnChallenge: Bool { get }

}

public extension RequestParameters {

    var refreshesOnChallenge: Bool {
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
