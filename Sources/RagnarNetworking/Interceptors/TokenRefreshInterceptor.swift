//
//  TokenRefreshInterceptor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-15.
//

import Foundation

/// Protocol for providing token refresh functionality
public protocol TokenProvider: Sendable {
    /// Refresh the authentication token
    /// - Returns: The new authentication token
    func refreshToken() async throws -> String
}

/// Interceptor that handles token refresh on authentication failures
public actor TokenRefreshInterceptor: RequestInterceptor {

    private let tokenProvider: TokenProvider
    private let maxRetries: Int
    private var isRefreshing = false
    private var pendingRequests: [CheckedContinuation<String, Error>] = []

    /// Initialize a token refresh interceptor
    /// - Parameters:
    ///   - tokenProvider: Provider for refreshing tokens
    ///   - maxRetries: Maximum number of retry attempts (default: 1)
    public init(tokenProvider: TokenProvider, maxRetries: Int = 1) {
        self.tokenProvider = tokenProvider
        self.maxRetries = maxRetries
    }

    public func retry(
        _ request: URLRequest,
        for interface: any Interface.Type,
        dueTo error: Error,
        attemptNumber: Int
    ) async throws -> RetryResult {
        // Check if this is a 401 error and we haven't exceeded max retries
        guard attemptNumber <= maxRetries else {
            return .doNotRetry
        }

        // Check if error is an authentication error (401)
        let is401Error: Bool
        switch error {
        case ResponseError.unknownResponseCase(let httpResponse):
            is401Error = httpResponse.statusCode == 401
        default:
            is401Error = false
        }

        guard is401Error else {
            return .doNotRetry
        }

        // Refresh token
        let newToken = try await refreshTokenWithCoordination()

        // Modify request with new token
        var modifiedRequest = request
        modifiedRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

        return .retryWithModifiedRequest(modifiedRequest, afterDelay: 0.1)
    }

    /// Refresh token with coordination to prevent multiple simultaneous refreshes
    /// - Returns: The new authentication token
    private func refreshTokenWithCoordination() async throws -> String {
        // If already refreshing, wait for the result
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                pendingRequests.append(continuation)
            }
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let token = try await tokenProvider.refreshToken()

            // Resume all pending requests
            for continuation in pendingRequests {
                continuation.resume(returning: token)
            }
            pendingRequests.removeAll()

            return token
        } catch {
            // Fail all pending requests
            for continuation in pendingRequests {
                continuation.resume(throwing: error)
            }
            pendingRequests.removeAll()
            throw error
        }
    }

}
