//
//  ExponentialBackoffInterceptor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-15.
//

import Foundation

/// Interceptor that implements exponential backoff retry logic
public struct ExponentialBackoffInterceptor: RequestInterceptor {

    /// Conditions under which to retry
    public enum RetryCondition: Sendable {
        /// Retry on any network error
        case networkErrors
        /// Retry on specific HTTP status codes
        case httpStatusCodes(Set<Int>)
        /// Retry on server errors (5xx)
        case serverErrors
        /// Custom condition
        case custom(@Sendable (Error) -> Bool)
    }

    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let retryCondition: RetryCondition

    /// Initialize an exponential backoff interceptor
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - baseDelay: Base delay in seconds for exponential calculation (default: 1.0)
    ///   - retryCondition: Condition determining when to retry (default: server errors)
    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        retryCondition: RetryCondition = .serverErrors
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.retryCondition = retryCondition
    }

    public func retry(
        _ request: URLRequest,
        for interface: any Interface.Type,
        dueTo error: Error,
        attemptNumber: Int
    ) async throws -> RetryResult {
        // Check if we've exceeded max retries
        guard attemptNumber <= maxRetries else {
            return .doNotRetry
        }

        // Check if this error matches our retry condition
        guard shouldRetry(error: error) else {
            return .doNotRetry
        }

        // Calculate exponential backoff delay: baseDelay * 2^(attemptNumber - 1)
        // Attempt 1: baseDelay * 1 = 1s
        // Attempt 2: baseDelay * 2 = 2s
        // Attempt 3: baseDelay * 4 = 4s
        let delay = baseDelay * pow(2.0, Double(attemptNumber - 1))

        return .retry(afterDelay: delay)
    }

    /// Determine if the error matches the retry condition
    /// - Parameter error: The error to check
    /// - Returns: True if the error should trigger a retry
    private func shouldRetry(error: Error) -> Bool {
        switch retryCondition {
        case .networkErrors:
            // Retry on URLErrors (network issues)
            return error is URLError

        case .httpStatusCodes(let statusCodes):
            // Retry on specific HTTP status codes
            if case ResponseError.unknownResponseCase(let httpResponse) = error {
                return statusCodes.contains(httpResponse.statusCode)
            }
            return false

        case .serverErrors:
            // Retry on 5xx server errors
            if case ResponseError.unknownResponseCase(let httpResponse) = error {
                return (500...599).contains(httpResponse.statusCode)
            }
            return false

        case .custom(let condition):
            // Use custom condition
            return condition(error)
        }
    }

}
