//
//  DefaultResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// The built-in response handler. Matches status codes against `Interface.responses`,
/// decodes success bodies, and throws typed `ResponseError` values for failures.
///
/// Set `ServerConfiguration.responseHandler` to replace this across a whole API, or override
/// `Interface.responseHandler` to replace it for one endpoint.
///
/// A custom `ResponseHandler` that wants the default behavior plus a targeted addition
/// (for example, inspecting a header before decoding) can delegate to `handle`, or reuse
/// `decode` alone when it drives its own status matching:
///
/// ```swift
/// struct LoggingResponseHandler: ResponseHandler {
///     private let base = DefaultResponseHandler()
///
///     func handle<T: Interface>(
///         _ response: (data: Data, response: URLResponse),
///         for interface: T.Type,
///         context: ResponseContext
///     ) throws(ResponseError) -> T.Response {
///         // Inspect the raw response before the default handling runs.
///         log(response.response)
///         return try base.handle(response, for: interface, context: context)
///     }
/// }
/// ```
public struct DefaultResponseHandler: ResponseHandler {

    /// Creates the default handler. Stateless; create one wherever you need it.
    public init() {}

    /// Matches the response's status code against `Interface.responses`, then decodes the
    /// body as the Interface's `Response` or throws the mapped error.
    ///
    /// A no-body success builds the declared `Response` against zero bytes: `EmptyResponse`,
    /// `Data`, and `String` all build themselves from an empty body.
    public func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        context: ResponseContext
    ) throws(ResponseError) -> T.Response {
        let responseDecoder = context.responseDecoder
        let responseSnapshot = HTTPResponseSnapshot(
            response: response.response,
            redactedQueryItemNames: context.redactedQueryItemNames
        )
        let responseBody = ResponseBody(response.data, decoder: responseDecoder)

        guard let statusCode = responseSnapshot.statusCode else {
            throw .unknownResponse(
                responseBody,
                responseSnapshot
            )
        }

        guard let responseMatch = interface.responses.match(statusCode) else {
            throw .unknownResponseCase(
                responseBody,
                responseSnapshot
            )
        }

        switch responseMatch {
        case .success:
            do {
                return try decode(
                    response.data,
                    as: interface,
                    metadata: responseSnapshot,
                    responseDecoder: responseDecoder
                )
            } catch {
                throw .decoding(
                    responseBody,
                    responseSnapshot,
                    error
                )
            }

        case .failure(.error(let error)):
            throw .generic(
                responseBody,
                responseSnapshot,
                error
            )

        case .failure(.decodeError(body: let decodeBody)):
            // Decoding failures from custom closures are surfaced as
            // ResponseError.decoding with structured diagnostics when possible.
            let decodedError: any Error & Sendable
            do {
                decodedError = try decodeBody(response.data, responseDecoder)
            } catch {
                if let decodingError = error as? DecodingError {
                    throw .decoding(
                        responseBody,
                        responseSnapshot,
                        .jsonDecoder(.init(decodingError))
                    )
                }
                throw .decoding(
                    responseBody,
                    responseSnapshot,
                    .custom(message: String(describing: error))
                )
            }

            throw .decoded(
                responseBody,
                responseSnapshot,
                decodedError
            )
        }
    }

    /// Decodes `data` as `T.Response` by asking the response type itself, and normalizes
    /// whatever it throws into an `InterfaceDecodingError`. Call this when composing custom
    /// decoding logic that drives its own status matching but still wants the default
    /// type-driven decoding.
    ///
    /// - Parameter metadata: Passed through to `InterfaceResponse.decode`, for response types
    ///   whose value depends on a header or the status code.
    public func decode<T: Interface>(
        _ data: Data,
        as interface: T.Type,
        metadata: HTTPResponseSnapshot,
        responseDecoder: ResponseDecoder
    ) throws(InterfaceDecodingError) -> T.Response {
        do {
            return try T.Response.decode(
                from: data,
                metadata: metadata,
                using: responseDecoder
            )
        } catch let error as InterfaceDecodingError {
            throw error
        } catch let error as DecodingError {
            throw .jsonDecoder(.init(error))
        } catch {
            throw .custom(message: String(describing: error))
        }
    }

}
