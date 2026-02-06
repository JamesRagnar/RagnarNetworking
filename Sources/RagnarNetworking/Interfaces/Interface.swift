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

    /// The expected response type when the request succeeds
    associatedtype Response: Decodable, Sendable

    /// Defines how each HTTP status code should be handled for this interface
    static var responseCases: ResponseMap { get }

    /// Defines how responses are decoded and mapped to the Interface Response.
    static var responseHandler: ResponseHandler.Type { get }

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

    /// Optional query parameters to append to the URL
    var queryItems: [String: String?]? { get }

    /// Optional HTTP headers to include in the request
    var headers: [String: String]? { get }

    /// The concrete body type for this request.
    /// Defaults to EmptyBody for requests without a body.
    associatedtype Body: RequestBody = EmptyBody

    /// Optional request body data. Set to nil for requests without a body.
    var body: Body? { get }

    /// The authentication strategy for this request
    var authentication: AuthenticationType { get }

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

// MARK: Authentication Type

/// Specifies how authentication credentials should be included in a request.
public enum AuthenticationType: Sendable {

    /// No authentication required for this request
    case none

    /// Authentication token included in request headers as `Authorization: Bearer <token>`
    case bearer

    /// Authentication token included in query parameters as `?token=<token>`
    case url

}
