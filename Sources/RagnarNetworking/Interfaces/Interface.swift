//
//  Interface.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// Defines the contract for a network request endpoint, including its parameters, response type, and status code handling.
///
/// Conform to this protocol to create type-safe API endpoint definitions. The protocol connects
/// request parameters with their expected response types and defines how different HTTP status
/// codes should be interpreted.
public protocol Interface: Sendable {

    /// The parameters defining how to construct the network request
    associatedtype Parameters: RequestParameters

    /// The expected response type when the request succeeds
    associatedtype Response: Decodable, Sendable

    /// Maps HTTP status codes to their expected outcomes (success with a type, or a specific error)
    typealias ResponseCases = [Int: Result<Response.Type, Error>]

    /// Defines how each HTTP status code should be handled for this interface
    static var responseCases: ResponseCases { get }

}
