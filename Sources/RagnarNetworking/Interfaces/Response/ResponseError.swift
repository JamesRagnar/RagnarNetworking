//
//  ResponseError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Errors that can occur when processing HTTP responses.
///
/// Each error case includes the raw response data and HTTP response for debugging purposes,
/// allowing you to inspect the actual server response when something goes wrong.
public enum ResponseError: LocalizedError, Sendable {

    /// The response could not be cast to HTTPURLResponse
    case unknownResponse(Data, HTTPResponseSnapshot)

    /// The HTTP status code is not defined in the Interface's response cases
    case unknownResponseCase(Data, HTTPResponseSnapshot)

    /// The response data could not be decoded to the expected type
    case decoding(Data, HTTPResponseSnapshot, InterfaceDecodingError)

    /// A predefined error was returned for this status code
    case generic(Data, HTTPResponseSnapshot, any Error & Sendable)

    /// A decoded error body was returned for this status code
    /// - Note: The decoded error is stored for type-safe access without re-decoding.
    case decoded(Data, HTTPResponseSnapshot, any Error & Sendable)

}

/// A Sendable snapshot of an HTTP response.
public struct HTTPResponseSnapshot: Sendable {

    public let isHTTPResponse: Bool

    public let statusCode: Int?

    public let headers: [String: String]

    public let url: URL?

    public let mimeType: String?

    public let expectedContentLength: Int64

    public let textEncodingName: String?

    public init(response: URLResponse) {
        let httpResponse = response as? HTTPURLResponse
        self.isHTTPResponse = httpResponse != nil
        self.statusCode = httpResponse?.statusCode
        self.headers = Self.coerceHeaders(httpResponse?.allHeaderFields ?? [:])
        self.url = response.url
        self.mimeType = response.mimeType
        self.expectedContentLength = response.expectedContentLength
        self.textEncodingName = response.textEncodingName
    }

    static func coerceHeaders(_ rawHeaders: [AnyHashable: Any]) -> [String: String] {
        var coercedHeaders: [String: String] = [:]
        coercedHeaders.reserveCapacity(rawHeaders.count)
        for (key, value) in rawHeaders {
            coercedHeaders[String(describing: key)] = String(describing: value)
        }
        return coercedHeaders
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
    /// Returns `nil` when the response was not an HTTP response.
    var headers: [String: String]? {
        switch self {
        case .unknownResponse(_, let response),
             .unknownResponseCase(_, let response),
             .decoding(_, let response, _),
             .generic(_, let response, _),
             .decoded(_, let response, _):
            return response.isHTTPResponse ? response.headers : nil
        }
    }

    /// Returns the value of a specific header field.
    ///
    /// Lookup is case-insensitive per HTTP semantics.
    ///
    /// - Parameter key: The header field name
    /// - Returns: The header value, or `nil` if the header is not present
    func header(_ key: String) -> String? {
        guard let headers else { return nil }
        return headers.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value
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

    /// A concise localized description intended for user-facing display.
    var errorDescription: String? {
        switch self {
        case .unknownResponse:
            return "Received a non-HTTP response."

        case .unknownResponseCase(_, let snapshot):
            if let statusCode = snapshot.statusCode {
                return "Received an unhandled HTTP status code (\(statusCode))."
            }
            return "Received an unhandled response."

        case .decoding:
            return "Failed to decode the server response."

        case .generic(_, _, let error),
             .decoded(_, _, let error):
            return String(describing: error)
        }
    }

}
