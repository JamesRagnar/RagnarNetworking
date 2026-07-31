//
//  DefaultResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// The built-in response handler. Matches status codes against `Interface.responseCases`,
/// decodes success bodies, and throws typed `ResponseError` values for failures.
///
/// Override `Interface.responseHandler` to replace this with custom logic per-interface.
///
/// A custom `ResponseHandler` that wants the default behavior plus a targeted addition
/// (for example, inspecting a header before decoding) can compose with `handleOutcome`
/// and `decode` instead of reimplementing `handle` from scratch:
///
/// ```swift
/// struct LoggingResponseHandler: ResponseHandler {
///     private let base = DefaultResponseHandler()
///
///     func handle<T: Interface>(
///         _ response: (data: Data, response: URLResponse),
///         for interface: T.Type,
///         responseDecoder: ResponseDecoder
///     ) throws(ResponseError) -> T.Response {
///         // Inspect the raw response before the default handling runs.
///         switch try base.handleOutcome(response, for: interface, responseDecoder: responseDecoder) {
///         case .decoded(let value):
///             return value
///         case .noContent:
///             do {
///                 return try base.decode(Data(), as: interface, responseDecoder: responseDecoder)
///             } catch {
///                 throw .decoding(
///                     ResponseBody(response.data, decoder: responseDecoder),
///                     HTTPResponseSnapshot(response: response.response),
///                     error
///                 )
///             }
///         }
///     }
/// }
/// ```
public struct DefaultResponseHandler: ResponseHandler {

    /// Creates the default handler. Stateless; create one wherever you need it.
    public init() {}

    /// Matches the response's status code against `Interface.responseCases`, then decodes the
    /// success body, resolves a no-content success, or throws the mapped error.
    public func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        responseDecoder: ResponseDecoder
    ) throws(ResponseError) -> T.Response {
        switch try handleOutcome(response, for: interface, responseDecoder: responseDecoder) {
        case .decoded(let value):
            return value

        case .noContent:
            do {
                return try decode(Data(), as: interface, responseDecoder: responseDecoder)
            } catch {
                throw .decoding(
                    ResponseBody(response.data, decoder: responseDecoder),
                    HTTPResponseSnapshot(response: response.response),
                    error
                )
            }
        }
    }

    /// Matches the response's status code against `Interface.responseCases` and either
    /// decodes the success body, reports a no-content success, or throws the mapped error -
    /// without deciding what to do for the no-content case, unlike `handle`. Call this first
    /// when composing a custom `ResponseHandler` on top of the default status-code matching.
    public func handleOutcome<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        responseDecoder: ResponseDecoder
    ) throws(ResponseError) -> ResponseOutcomeResult<T.Response> {
        let responseSnapshot = HTTPResponseSnapshot(response: response.response)
        let responseBody = ResponseBody(response.data, decoder: responseDecoder)

        guard let statusCode = responseSnapshot.statusCode else {
            throw .unknownResponse(
                responseBody,
                responseSnapshot
            )
        }

        guard let responseCase = interface.responseCases.match(statusCode) else {
            throw .unknownResponseCase(
                responseBody,
                responseSnapshot
            )
        }

        switch responseCase {
        case .decode:
            do {
                return .decoded(try decode(response.data, as: interface, responseDecoder: responseDecoder))
            } catch {
                throw .decoding(
                    responseBody,
                    responseSnapshot,
                    error
                )
            }

        case .noContent:
            return .noContent

        case .error(let error):
            throw .generic(
                responseBody,
                responseSnapshot,
                error
            )

        case .decodeError(body: let decodeBody):
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

    /// Decodes `data` as `T.Response`, handling the `EmptyResponse`, `String`, and `Data`
    /// special cases before falling back to `responseDecoder`. Call this to finish handling
    /// once `handleOutcome` reports `.noContent` (with an empty `Data`) or when composing
    /// custom decoding logic that still needs the default type-driven behavior.
    public func decode<T: Interface>(
        _ data: Data,
        as interface: T.Type,
        responseDecoder: ResponseDecoder
    ) throws(InterfaceDecodingError) -> T.Response {
        if T.Response.self == EmptyResponse.self {
            guard let empty = EmptyResponse() as? T.Response else {
                throw .custom(message: "EmptyResponse cast failed for \(T.Response.self)")
            }
            return empty
        }

        if T.Response.self == String.self {
            guard let response = String(
                data: data,
                encoding: .utf8
            ) as? T.Response else {
                throw .missingString
            }

            return response
        }

        if T.Response.self == Data.self {
            guard let responseData = data as? T.Response else {
                throw .missingData
            }

            return responseData
        }

        do {
            return try responseDecoder.makeJSONDecoder().decode(
                T.Response.self,
                from: data
            )
        } catch {
            if let decodingError = error as? DecodingError {
                throw .jsonDecoder(.init(decodingError))
            }

            throw .custom(message: String(describing: error))
        }
    }

}
