//
//  DataTaskProvider.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-21.
//

import Foundation.NSURLSession

/// Abstracts the execution of network requests, allowing for dependency injection and testing.
///
/// This protocol defines the interface for executing network requests. `URLSession` conforms to
/// this protocol by default, but you can provide custom implementations for testing or specialized
/// networking behavior.
public protocol DataTaskProvider: Sendable {

    /// Executes a type-safe network request using an Interface definition.
    /// - Parameters:
    ///   - interface: The interface type defining the request/response contract
    ///   - parameters: The parameters for constructing the request
    ///   - configuration: Server configuration including base URL and auth token
    /// - Returns: The decoded response matching the interface's Response type
    /// - Throws: `RequestError` for request construction issues, `ResponseError` for response handling issues
    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) async throws -> T.Response

    /// Executes a raw URLRequest and returns the response data.
    /// - Parameter request: The URLRequest to execute
    /// - Returns: A tuple containing the response data and URLResponse
    /// - Throws: Network or protocol errors
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

}

// MARK: - Default Implementation

public extension DataTaskProvider {

    /// Default implementation that constructs a URLRequest from Interface parameters,
    /// executes it, and handles the response according to the Interface's response cases.
    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) async throws -> T.Response {
        let request = try URLRequest(
            requestParameters: parameters,
            serverConfiguration: configuration
        )

        let response = try await data(for: request)

        return try T.handle(response)
    }

}

// MARK: - URLSession Conformance

extension URLSession: DataTaskProvider {}
