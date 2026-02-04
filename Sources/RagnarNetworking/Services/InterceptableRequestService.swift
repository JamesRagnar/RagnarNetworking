//
//  InterceptableRequestService.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-15.
//

import Foundation

/// Concrete implementation of RequestService with interceptor support
open class InterceptableRequestService: RequestService {

    public let loggingService: LoggingService?
    public let dataTaskProvider: any DataTaskProvider
    public let interceptors: [RequestInterceptor]
    public let constructor: InterfaceConstructor.Type

    private let configurationProvider: @Sendable () throws -> ServerConfiguration

    /// Initialize an interceptable request service
    /// - Parameters:
    ///   - dataTaskProvider: Provider for executing network requests
    ///   - configurationProvider: Closure providing server configuration
    ///   - interceptors: Array of interceptors to apply to requests
    ///   - loggingService: Optional logging service
    public init(
        dataTaskProvider: any DataTaskProvider = URLSession.shared,
        configurationProvider: @escaping @Sendable () throws -> ServerConfiguration,
        interceptors: [RequestInterceptor] = [],
        loggingService: LoggingService? = nil,
        constructor: InterfaceConstructor.Type = URLRequest.self
    ) {
        self.dataTaskProvider = dataTaskProvider
        self.configurationProvider = configurationProvider
        self.interceptors = interceptors
        self.loggingService = loggingService
        self.constructor = constructor
    }

    public func serverConfiguration() throws -> ServerConfiguration {
        return try configurationProvider()
    }

    /// Execute a data task with interceptor support
    /// - Parameters:
    ///   - interface: The interface type defining the request/response contract
    ///   - parameters: The parameters for the request
    /// - Returns: The decoded response
    public func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters
    ) async throws -> T.Response {
        var request = try constructor.buildRequest(
            requestParameters: parameters,
            serverConfiguration: try serverConfiguration()
        )

        // Apply adapters from all interceptors
        for interceptor in interceptors {
            request = try await interceptor.adapt(request, for: interface)
        }

        // Execute with retry logic
        return try await executeWithRetry(request, for: interface, attemptNumber: 1)
    }

    /// Execute a request with retry support
    /// - Parameters:
    ///   - request: The URLRequest to execute
    ///   - interface: The interface type
    ///   - attemptNumber: The current attempt number (1-indexed)
    /// - Returns: The decoded response
    private func executeWithRetry<T: Interface>(
        _ request: URLRequest,
        for interface: T.Type,
        attemptNumber: Int
    ) async throws -> T.Response {
        loggingService?.log(
            source: .requestService,
            level: .debug,
            message: "\(request.httpMethod ?? "") - \(request.url?.description ?? "") (attempt \(attemptNumber))"
        )

        do {
            let response = try await dataTaskProvider.data(for: request)
            return try T.handle(response)
        } catch {
            let errorMessage: String
            if let responseError = error as? ResponseError {
                errorMessage = "Request error (attempt \(attemptNumber)) - \(responseError.debugDescription)"
            } else {
                errorMessage = "Request error (attempt \(attemptNumber)) - \(error.localizedDescription)"
            }

            loggingService?.log(
                source: .requestService,
                level: .error,
                message: errorMessage
            )

            // Check interceptors for retry
            for interceptor in interceptors {
                let retryResult = try await interceptor.retry(
                    request,
                    for: interface,
                    dueTo: error,
                    attemptNumber: attemptNumber
                )

                switch retryResult {
                case .doNotRetry:
                    continue

                case .retry(let delay):
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    return try await executeWithRetry(request, for: interface, attemptNumber: attemptNumber + 1)

                case .retryWithModifiedRequest(let modifiedRequest, let delay):
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    return try await executeWithRetry(modifiedRequest, for: interface, attemptNumber: attemptNumber + 1)
                }
            }

            // No interceptor handled it, rethrow
            throw error
        }
    }

}
