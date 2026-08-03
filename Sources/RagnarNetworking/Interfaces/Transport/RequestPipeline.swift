//
//  RequestPipeline.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// Runs one Interface request end to end: build → transport → handle.
///
/// Holds the `Transport` and nothing else; the builder, coding, headers, and default response
/// handler all arrive on the `RequestContext`. `APIClient` layers credentials and retry on top,
/// but the pipeline is usable directly when a caller manages its own token.
///
/// ```swift
/// let pipeline = RequestPipeline(transport: URLSession.shared)
/// let context = RequestContext(configuration: configuration, credential: token)
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
    /// - Throws: `RequestError` for request construction and credential application,
    ///   `TransportError` for connection failures, `ResponseError` for response handling, and
    ///   `CancellationError` if the call was cancelled.
    public func send<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        context: RequestContext
    ) async throws -> T.Response {
        let request = try URLRequest(requestParameters: parameters, context: context)

        // `Transport.data(for:)` is untyped `throws` by design, so whatever it throws is
        // classified here rather than escaping as a raw `URLError` a caller has to know to
        // catch and switch on.
        let response: (Data, URLResponse)
        do {
            response = try await transport.data(for: request)
        } catch {
            // Cancellation stays `CancellationError` whichever side raised it: the package, or
            // `URLSession` reporting `URLError.cancelled`. One check covers both.
            if error is CancellationError {
                throw error
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw TransportError.classifying(error)
        }

        return try T.handle(
            response,
            context: context.responseContext,
            defaultHandler: context.responseHandler
        )
    }

}
