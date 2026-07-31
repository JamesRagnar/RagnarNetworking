//
//  RequestPipeline.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// Runs one Interface request end to end: build → transport → handle.
///
/// The pipeline owns the composition of a `RequestBuilder` and a `Transport`; each of those
/// owns exactly one job. `APIClient` layers credentials and retry on top, but the pipeline is
/// usable directly when a caller manages its own token.
///
/// ```swift
/// let pipeline = RequestPipeline(transport: URLSession.shared)
/// let context = RequestContext(configuration: configuration, authToken: token)
/// let user = try await pipeline.send(GetUser.self, .init(id: id), context: context)
/// ```
public struct RequestPipeline: Sendable {

    /// Executes the built request.
    public let transport: any Transport

    /// Builds the `URLRequest` from Interface parameters.
    public let builder: any RequestBuilder

    /// Creates a pipeline.
    /// - Parameters:
    ///   - transport: The underlying transport. Defaults to `URLSession.shared`.
    ///   - builder: Builds requests from Interface parameters. Defaults to `URLRequestBuilder()`.
    public init(
        transport: any Transport = URLSession.shared,
        builder: any RequestBuilder = URLRequestBuilder()
    ) {
        self.transport = transport
        self.builder = builder
    }

    /// Builds, executes, and handles a type-safe Interface request.
    ///
    /// The context's `responseDecoder` is threaded into response handling, so success bodies
    /// and typed error bodies decode with the same configured rules.
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
        let request = try builder.buildRequest(parameters, context: context)

        let response = try await transport.data(for: request)

        return try T.handle(response, responseDecoder: context.responseDecoder)
    }

}
