//
//  Interface+ResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

// MARK: - Response Handling

public extension Interface {

    /// Default response handler for Interfaces.
    static var responseHandler: ResponseHandler.Type {
        DefaultResponseHandler.self
    }

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
        return try responseHandler.handle(response, for: Self.self)
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
    /// Returns the status code when available, otherwise `nil`.
    var statusCode: Int? {
        switch self {
        case .unknownResponse(_, let snapshot),
             .unknownResponseCase(_, let snapshot),
             .decoding(_, let snapshot, _),
             .generic(_, let snapshot, _),
             .decoded(_, let snapshot, _):
            return snapshot.statusCode
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

        return .init(
            data: data,
            encoding: .utf8
        )
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
    /// Returns all HTTP headers for the response when available.
    var headers: [String: String]? {
        switch self {
        case .unknownResponse(_, let response),
             .unknownResponseCase(_, let response),
             .decoding(_, let response, _),
             .generic(_, let response, _),
             .decoded(_, let response, _):
            return response.headers
        }
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
