//
//  Transport.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-21.
//

import Foundation.NSURLSession

/// Abstracts the execution of a single `URLRequest`, allowing for dependency injection and testing.
///
/// A transport moves bytes and nothing else. Building requests and interpreting responses belong
/// to `RequestPipeline`.
///
/// `URLSession` conforms by default.
///
/// - Note: Bodies are buffered in memory in both directions. Streamed upload and download are
///   out of scope; use `URLSession` directly for those.
public protocol Transport: Sendable {

    /// Executes a raw URLRequest and returns the response data.
    /// - Parameter request: The URLRequest to execute
    /// - Returns: A tuple containing the response data and URLResponse
    /// - Throws: Network or protocol errors
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

}
