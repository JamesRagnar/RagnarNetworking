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
    /// - Throws: `APIFailure.request` when the request could not be built or the credential
    ///   could not be applied, `.transport` when the transport failed, `.response` when the
    ///   response could not be interpreted, and `.cancelled` when the call was cancelled. The
    ///   remaining cases belong to `APIClient` and are never thrown here.
    public func send<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        context: RequestContext
    ) async throws(APIFailure) -> T.Response {
        let request: URLRequest
        do {
            request = try URLRequest(requestParameters: parameters, context: context)
        } catch {
            throw .request(error)
        }

        // `Transport.data(for:)` is untyped `throws` by design, so whatever a custom transport
        // throws is classified here rather than escaping unwrapped.
        let response: (Data, URLResponse)
        do {
            response = try await transport.data(for: request)
        } catch {
            throw .classifying(error)
        }

        do {
            return try T.handle(
                response,
                context: context.responseContext,
                defaultHandler: context.responseHandler
            )
        } catch {
            throw .response(error)
        }
    }

}
