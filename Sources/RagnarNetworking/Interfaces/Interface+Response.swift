//
//  Interface+Response.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

// MARK: - Response Errors

/// Errors that can occur when processing HTTP responses.
///
/// Each error case includes the raw response data and HTTP response for debugging purposes,
/// allowing you to inspect the actual server response when something goes wrong.
public enum ResponseError: LocalizedError {

    /// The response could not be cast to HTTPURLResponse
    case unknownResponse(Data, URLResponse)

    /// The HTTP status code is not defined in the Interface's response cases
    case unknownResponseCase(Data, HTTPURLResponse)

    /// The response data could not be decoded to the expected type
    case decoding(Data, HTTPURLResponse, InterfaceDecodingError)

    /// A predefined error was returned for this status code
    case generic(Data, HTTPURLResponse, Error)

    /// A decoded error body was returned for this status code
    /// - Note: The decoded error is stored for type-safe access without re-decoding.
    case decoded(Data, HTTPURLResponse, any Error & Sendable)

}

/// Specific errors encountered during response decoding.
public enum InterfaceDecodingError: Error {

    /// Expected String response but UTF-8 decoding failed
    case missingString

    /// Expected Data response but type casting failed
    case missingData

    /// JSON decoding failed with the underlying error
    case jsonDecoder(Error)

}

// MARK: - Response Outcome Result

/// The result of a handled response, allowing non-decoding success cases.
public enum ResponseOutcomeResult<Response: Sendable>: Sendable {

    /// The response was decoded as the Interface's Response type.
    case decoded(Response)

    /// The response was a success with no body (e.g., 204/205/304).
    case noContent

}

// MARK: - Response Handling

public extension Interface {

    /// Processes a raw HTTP response according to the Interface's response cases.
    ///
    /// This method validates the response type, checks the status code against the Interface's
    /// defined response cases, and either decodes a success response or throws the appropriate error.
    ///
    /// - Parameter response: Tuple containing the response data and URLResponse
    /// - Returns: The decoded Response type
    /// - Throws: `ResponseError` if the response cannot be processed
    static func handle(
        _ response: (data: Data, response: URLResponse)
    ) throws(ResponseError) -> Response {
        switch try handleOutcome(response) {
        case .decoded(let value):
            return value

        case .noContent:
            do {
                return try decode(response: Data())
            } catch {
                let httpResponse = response.response as! HTTPURLResponse
                throw .decoding(
                    response.data,
                    httpResponse,
                    error
                )
            }
        }
    }

    /// Processes a raw HTTP response and returns an explicit outcome.
    ///
    /// Use this when your Interface expects a success with no body (204/205/304).
    static func handleOutcome(
        _ response: (data: Data, response: URLResponse)
    ) throws(ResponseError) -> ResponseOutcomeResult<Response> {
        guard let httpResponse = response.response as? HTTPURLResponse else {
            throw .unknownResponse(
                response.data,
                response.response
            )
        }

        guard let responseCase = responseCases.match(httpResponse.statusCode) else {
            throw .unknownResponseCase(
                response.data,
                httpResponse
            )
        }

        switch responseCase {
        case .decode:
            do {
                return .decoded(try decode(response: response.data))
            } catch {
                throw .decoding(
                    response.data,
                    httpResponse,
                    error
                )
            }

        case .noContent:
            return .noContent

        case .error(let error):
            throw .generic(
                response.data,
                httpResponse,
                error
            )

        case .decodeError(body: let decodeBody):
            // Decoding failures are surfaced as ResponseError.decoding(.jsonDecoder).
            let decodedError: any Error & Sendable
            do {
                decodedError = try decodeBody(response.data)
            } catch {
                throw .decoding(
                    response.data,
                    httpResponse,
                    .jsonDecoder(error)
                )
            }
            throw .decoded(
                response.data,
                httpResponse,
                decodedError
            )
        }
    }

    /// Decodes response data to the Interface's Response type.
    ///
    /// Supports three response types:
    /// - String: Decodes data as UTF-8 string
    /// - Data: Returns raw data
    /// - Decodable: Uses JSONDecoder to decode the type
    ///
    /// - Parameter data: The raw response data
    /// - Returns: The decoded Response instance
    /// - Throws: `InterfaceDecodingError` if decoding fails
    static func decode(response data: Data) throws(InterfaceDecodingError) -> Response {
        if Response.self == String.self {
            guard let response = String(
                data: data,
                encoding: .utf8
            ) as? Response else {
                throw .missingString
            }

            return response
        }

        if Response.self == Data.self {
            guard let responseData = data as? Response else {
                throw .missingData
            }

            return responseData
        }

        do {
            return try JSONDecoder().decode(
                Response.self,
                from: data
            )
        } catch {
            throw .jsonDecoder(error)
        }
    }

}

// MARK: - Error Inspection Helpers

/// Convenience methods for inspecting and debugging `ResponseError` instances.
///
/// These helpers extract common information from the error's associated values,
/// making it easier to handle errors and debug issues without pattern matching.
public extension ResponseError {

    /// The HTTP status code from the response.
    ///
    /// Returns `nil` for `unknownResponse` (non-HTTP responses), otherwise returns
    /// the status code from the HTTPURLResponse.
    var statusCode: Int? {
        switch self {
        case .unknownResponse:
            return nil

        case .unknownResponseCase(_, let httpResponse),
             .decoding(_, let httpResponse, _),
             .generic(_, let httpResponse, _),
             .decoded(_, let httpResponse, _):
            return httpResponse.statusCode
        }
    }

    /// The response body as a UTF-8 string.
    ///
    /// Useful for logging or displaying error messages from the server.
    /// Returns `nil` if the data cannot be decoded as UTF-8.
    var responseBodyString: String? {
        let data: Data
        switch self {
        case .unknownResponse(let responseData, _),
             .unknownResponseCase(let responseData, _),
             .decoding(let responseData, _, _),
             .generic(let responseData, _, _),
             .decoded(let responseData, _, _):
            data = responseData
        }

        return String(data: data, encoding: .utf8)
    }

    /// Attempts to decode the error response body as a structured error type.
    ///
    /// If the error was created with `ResponseOutcome.decodeError`, this method will
    /// return the already-decoded error when it matches the requested type.
    ///
    /// Many APIs return structured error responses (e.g., `{"error": "message", "code": 123}`).
    /// This method attempts to decode the raw response data as your custom error type.
    ///
    /// - Parameter type: The Decodable type representing your API's error structure
    /// - Returns: The decoded error instance, or `nil` if decoding fails
    func decodeError<T: Decodable>(as type: T.Type) -> T? {
        if case .decoded(_, _, let decodedError) = self,
           let typed = decodedError as? T {
            return typed
        }

        let data: Data
        switch self {
        case .unknownResponse(let responseData, _),
             .unknownResponseCase(let responseData, _),
             .decoding(let responseData, _, _),
             .generic(let responseData, _, _),
             .decoded(let responseData, _, _):
            data = responseData
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    /// All HTTP headers from the response.
    ///
    /// Returns `nil` for `unknownResponse` (non-HTTP responses), otherwise returns
    /// the header dictionary from the HTTPURLResponse.
    var headers: [String: String]? {
        let httpResponse: HTTPURLResponse?
        switch self {
        case .unknownResponse:
            httpResponse = nil

        case .unknownResponseCase(_, let response),
             .decoding(_, let response, _),
             .generic(_, let response, _),
             .decoded(_, let response, _):
            httpResponse = response
        }

        return httpResponse?.allHeaderFields as? [String: String]
    }

    /// Returns the value of a specific header field.
    ///
    /// Useful for extracting specific headers like "X-Request-ID" or "Retry-After".
    ///
    /// - Parameter key: The header field name (case-sensitive)
    /// - Returns: The header value, or `nil` if the header is not present
    func header(_ key: String) -> String? {
        return headers?[key]
    }

    /// Indicates whether this error represents a retryable failure.
    ///
    /// Returns `true` for server errors (5xx) and rate limiting (429), which typically
    /// indicate temporary issues that may succeed if retried. Client errors (4xx) return `false`.
    var isRetryable: Bool {
        guard let code = statusCode else {
            return false
        }

        return (500...599).contains(code) || code == 429
    }

    /// A comprehensive debug description including error type, status code, headers, and body preview.
    ///
    /// Provides all relevant error information in a single formatted string, useful for logging.
    /// The response body is truncated to 200 characters to prevent excessive log output.
    var debugDescription: String {
        var components: [String] = []

        // Error type
        switch self {
        case .unknownResponse:
            components.append("ResponseError.unknownResponse")

        case .unknownResponseCase:
            components.append("ResponseError.unknownResponseCase")

        case .decoding(_, _, let decodingError):
            components.append("ResponseError.decoding(\(decodingError))")

        case .generic(_, _, let error):
            components.append("ResponseError.generic(\(error))")

        case .decoded(_, _, let error):
            components.append("ResponseError.decoded(\(error))")
        }

        // Status code
        if let code = statusCode {
            components.append("Status: \(code)")
        }

        // Headers
        if let headers = headers, !headers.isEmpty {
            let headerStrings = headers.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            components.append("Headers: [\(headerStrings)]")
        }

        // Body preview (first 200 characters)
        if let body = responseBodyString {
            let preview = body.prefix(200)
            let suffix = body.count > 200 ? "..." : ""
            components.append("Body: \(preview)\(suffix)")
        }

        return components.joined(separator: " | ")
    }

}
