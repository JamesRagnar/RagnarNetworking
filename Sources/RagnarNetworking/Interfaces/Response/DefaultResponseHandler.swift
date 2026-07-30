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
/// enum LoggingResponseHandler: ResponseHandler {
///     static func handle<T: Interface>(
///         _ response: (data: Data, response: URLResponse),
///         for interface: T.Type
///     ) throws(ResponseError) -> T.Response {
///         // Inspect the raw response before the default handling runs.
///         switch try DefaultResponseHandler.handleOutcome(response, for: interface) {
///         case .decoded(let value):
///             return value
///         case .noContent:
///             do {
///                 return try DefaultResponseHandler.decode(Data(), as: interface)
///             } catch {
///                 throw .decoding(response.data, HTTPResponseSnapshot(response: response.response), error)
///             }
///         }
///     }
/// }
/// ```
public enum DefaultResponseHandler: ResponseHandler {

    public static func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> T.Response {
        switch try handleOutcome(response, for: interface) {
        case .decoded(let value):
            return value

        case .noContent:
            do {
                return try decode(Data(), as: interface)
            } catch {
                let responseSnapshot = HTTPResponseSnapshot(response: response.response)
                throw .decoding(
                    response.data,
                    responseSnapshot,
                    error
                )
            }
        }
    }

    /// Matches the response's status code against `Interface.responseCases` and either
    /// decodes the success body, reports a no-content success, or throws the mapped error -
    /// without deciding what to do for the no-content case, unlike `handle`. Call this first
    /// when composing a custom `ResponseHandler` on top of the default status-code matching.
    public static func handleOutcome<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> ResponseOutcomeResult<T.Response> {
        let responseSnapshot = HTTPResponseSnapshot(response: response.response)
        guard let statusCode = responseSnapshot.statusCode else {
            throw .unknownResponse(
                response.data,
                responseSnapshot
            )
        }

        guard let responseCase = interface.responseCases.match(statusCode) else {
            throw .unknownResponseCase(
                response.data,
                responseSnapshot
            )
        }

        switch responseCase {
        case .decode:
            do {
                return .decoded(try decode(response.data, as: interface))
            } catch {
                throw .decoding(
                    response.data,
                    responseSnapshot,
                    error
                )
            }

        case .noContent:
            return .noContent

        case .error(let error):
            throw .generic(
                response.data,
                responseSnapshot,
                error
            )

        case .decodeError(body: let decodeBody):
            // Decoding failures from custom closures are surfaced as
            // ResponseError.decoding with structured diagnostics when possible.
            let decodedError: any Error & Sendable
            do {
                decodedError = try decodeBody(response.data)
            } catch {
                if let decodingError = error as? DecodingError {
                    throw .decoding(
                        response.data,
                        responseSnapshot,
                        .jsonDecoder(.init(decodingError))
                    )
                }
                throw .decoding(
                    response.data,
                    responseSnapshot,
                    .custom(message: String(describing: error))
                )
            }

            throw .decoded(
                response.data,
                responseSnapshot,
                decodedError
            )
        }
    }

    /// Decodes `data` as `T.Response`, handling the `EmptyResponse`, `String`, and `Data`
    /// special cases before falling back to `JSONDecoder`. Call this to finish handling
    /// once `handleOutcome` reports `.noContent` (with an empty `Data`) or when composing
    /// custom decoding logic that still needs the default type-driven behavior.
    public static func decode<T: Interface>(
        _ data: Data,
        as interface: T.Type
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
            return try JSONDecoder().decode(
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
