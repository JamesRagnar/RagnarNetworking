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
/// to `RequestPipeline`, so there is exactly one thing to implement here and no way for a test
/// double to accidentally bypass request construction or response handling.
///
/// `URLSession` conforms by default.
///
/// - Note: Bodies are buffered in memory in both directions. Streamed upload from disk and
///   streamed download are deliberately out of scope; an endpoint that needs either is better
///   served by using `URLSession` directly than by widening this protocol.
public protocol Transport: Sendable {

    /// Executes a raw URLRequest and returns the response data.
    /// - Parameter request: The URLRequest to execute
    /// - Returns: A tuple containing the response data and URLResponse
    /// - Throws: Network or protocol errors
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

}
