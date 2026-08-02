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

    /// Whether this request carries a credential and should participate in challenge retry and
    /// coalesced refresh.
    ///
    /// Defaults to `authentication != nil`. Override it to `true` when the credential arrives by
    /// a route this package does not model - a cookie jar, a signing `Transport`, a proxy - and
    /// the request therefore declares no scheme; otherwise it gets no retry and no refresh.
    ///
    /// The only member here with a default implementation, because it is the only derived one.
    var isAuthenticated: Bool { get }

}

public extension RequestParameters {

    var isAuthenticated: Bool {
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
