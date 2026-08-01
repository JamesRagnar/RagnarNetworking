//
//  RequestPipeline.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// Runs one Interface request end to end: build → transport → handle.
///
/// The pipeline owns the algorithm and the `Transport`, and nothing else. Everything that
/// describes the server - builder, coding, headers, default response handler - arrives in the
/// `RequestContext`, so there is exactly one source of truth for it and no precedence rule to
/// remember. `APIClient` layers credentials and retry on top, but the pipeline is usable
/// directly when a caller manages its own token.
///
/// ```swift
/// let pipeline = RequestPipeline(transport: URLSession.shared)
/// let context = RequestContext(configuration: configuration, authToken: token)
/// let user = try await pipeline.send(GetUser.self, .init(id: id), context: context)
/// ```
public struct RequestPipeline: Sendable {

    /// Executes the built request.
    public let transport: any Transport

    /// Creates a pipeline.
    /// - Parameter transport: The underlying transport. Defaults to `URLSession.shared`.
    public init(transport: any Transport = URLSession.shared) {
        self.transport = transport
    }

    /// Builds, executes, and handles a type-safe Interface request.
    ///
    /// The context's `responseDecoder` is threaded into response handling, so success bodies
    /// and typed error bodies decode with the same configured rules. Response handling uses the
    /// Interface's own `responseHandler` when it declares one, and the context's otherwise.
    ///
    /// - Parameters:
    ///   - interface: The interface type defining the request/response contract
    ///   - parameters: The parameters for constructing the request
    ///   - context: Server configuration plus the credential for this request
    /// - Returns: The decoded response matching the interface's Response type
    /// - Throws: `RequestError` for request construction issues, `ResponseError` for response
    ///   handling issues, or the transport's own error for connection failures
    public func send<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        context: RequestContext
    ) async throws -> T.Response {
        let request = try context.builder.buildRequest(parameters, context: context)

        let response = try await transport.data(for: request)

        return try T.handle(
            response,
            responseDecoder: context.responseDecoder,
            defaultHandler: context.responseHandler
        )
    }

}
