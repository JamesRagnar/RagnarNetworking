//
//  RequestInterceptor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-15.
//

import Foundation

/// Protocol for intercepting and modifying requests and responses
public protocol RequestInterceptor: Sendable {

    /// Adapt the request before it's sent
    /// - Parameters:
    ///   - request: The original URLRequest
    ///   - interface: The interface type being used
    /// - Returns: The adapted URLRequest
    func adapt(
        _ request: URLRequest,
        for interface: any Interface.Type
    ) async throws -> URLRequest

    /// Determine whether to retry a failed request
    /// - Parameters:
    ///   - request: The URLRequest that failed
    ///   - interface: The interface type being used
    ///   - error: The error that occurred
    ///   - attemptNumber: The current attempt number (1-indexed)
    /// - Returns: A RetryResult indicating whether and how to retry
    func retry(
        _ request: URLRequest,
        for interface: any Interface.Type,
        dueTo error: Error,
        attemptNumber: Int
    ) async throws -> RetryResult

}

/// Result of a retry decision
public enum RetryResult: Sendable {
    /// Do not retry the request
    case doNotRetry

    /// Retry the same request after an optional delay
    case retry(afterDelay: TimeInterval = 0)

    /// Retry with a modified request after an optional delay
    case retryWithModifiedRequest(URLRequest, afterDelay: TimeInterval = 0)
}

// Default implementations (no-op)
public extension RequestInterceptor {

    func adapt(
        _ request: URLRequest,
        for interface: any Interface.Type
    ) async throws -> URLRequest {
        return request
    }

    func retry(
        _ request: URLRequest,
        for interface: any Interface.Type,
        dueTo error: Error,
        attemptNumber: Int
    ) async throws -> RetryResult {
        return .doNotRetry
    }

}
