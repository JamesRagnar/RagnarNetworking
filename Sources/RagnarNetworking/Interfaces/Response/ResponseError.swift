//
//  ResponseError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Errors that can occur when processing HTTP responses.
///
/// Each case carries the response body and a snapshot of the HTTP response, so the server's
/// actual response is available at the catch site. The body carries the decoder configured for
/// the response; `decodeError(as:)` uses it.
public enum ResponseError: LocalizedError, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    /// The response could not be cast to HTTPURLResponse
    case unknownResponse(ResponseBody, HTTPResponseSnapshot)

    /// The HTTP status code is not defined in the Interface's response cases
    case unknownResponseCase(ResponseBody, HTTPResponseSnapshot)

    /// The response body could not be decoded to the expected type
    case decoding(ResponseBody, HTTPResponseSnapshot, InterfaceDecodingError)

    /// A predefined error was returned for this status code
    case generic(ResponseBody, HTTPResponseSnapshot, any Error & Sendable)

    /// A decoded error body was returned for this status code
    /// - Note: The decoded error is stored for type-safe access without re-decoding.
    case decoded(ResponseBody, HTTPResponseSnapshot, any Error & Sendable)

}

/// A Sendable snapshot of an HTTP response.
public struct HTTPResponseSnapshot: Sendable {

    /// Whether the underlying `URLResponse` was an `HTTPURLResponse`. `statusCode` and
    /// `headers` are only meaningful when this is `true`.
    public let isHTTPResponse: Bool

    /// The HTTP status code, or `nil` if the response was not an `HTTPURLResponse`.
    public let statusCode: Int?

    /// All response headers, keyed by field name. Includes any `Set-Cookie` or
    /// `Authorization`/`Proxy-Authorization` echo the server sent - unlike
    /// `ResponseError`'s `debugDescription` and `description`, this property is not redacted.
    public let headers: [String: String]

    /// The request URL, with any credential-carrying query items removed so a captured snapshot
    /// does not leak a credential into a log line or a bug report.
    ///
    /// Which names those are comes from the configuration's registered `Authenticator` values,
    /// via `ServerConfiguration.redactedQueryItemNames`, so redaction cannot drift out of step
    /// with the parameter name a credential is actually written under.
    public let url: URL?

    public let mimeType: String?

    public let expectedContentLength: Int64

    public let textEncodingName: String?

    /// Captures a response.
    /// - Parameters:
    ///   - response: The response to snapshot
    ///   - redactedQueryItemNames: Query item names to strip from `url`, matched
    ///     case-insensitively. Normally `ResponseContext.redactedQueryItemNames`. Defaults to
    ///     empty, which redacts nothing.
    public init(
        response: URLResponse,
        redactedQueryItemNames: Set<String> = []
    ) {
        let httpResponse = response as? HTTPURLResponse
        self.isHTTPResponse = httpResponse != nil
        self.statusCode = httpResponse?.statusCode
        self.headers = Self.coerceHeaders(httpResponse?.allHeaderFields ?? [:])
        self.url = Self.redactingQueryItems(
            named: redactedQueryItemNames,
            from: response.url
        )
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

    /// Removes query items with any of the given names (case-insensitive) from `url`.
    static func redactingQueryItems(named names: Set<String>, from url: URL?) -> URL? {
        guard !names.isEmpty else { return url }

        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        func isRedacted(_ item: URLQueryItem) -> Bool {
            names.contains { $0.caseInsensitiveCompare(item.name) == .orderedSame }
        }

        guard let queryItems = components.queryItems,
              queryItems.contains(where: isRedacted)
        else {
            return url
        }

        let redactedQueryItems = queryItems.filter { !isRedacted($0) }
        components.queryItems = redactedQueryItems.isEmpty ? nil : redactedQueryItems
        return components.url ?? url
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

    /// The response body, paired with the decoder configured for the response it came from.
    var body: ResponseBody {
        switch self {
        case .unknownResponse(let responseBody, _),
             .unknownResponseCase(let responseBody, _),
             .decoding(let responseBody, _, _),
             .generic(let responseBody, _, _),
             .decoded(let responseBody, _, _):
            return responseBody
        }
    }

    /// The raw response bytes.
    var responseData: Data { body.data }

    /// The response body as a UTF-8 string.
    ///
    /// Useful for logging or displaying error messages from the server.
    /// Returns `nil` if the data cannot be decoded as UTF-8.
    var responseBodyString: String? { body.stringValue }

    /// Attempts to decode the error response body as a structured error type.
    ///
    /// If the error was created with `ResponseOutcome.decodeError`, this method will
    /// return the already-decoded error when it matches the requested type.
    ///
    /// Many APIs return structured error responses (e.g., `{"error": "message", "code": 123}`).
    /// This method decodes the raw response body as your custom error type, using the decoder
    /// the response was handled with - no need to re-supply the client's configuration here.
    ///
    /// - Parameter type: The Decodable type representing your API's error structure
    /// - Returns: The decoded error instance, or `nil` if decoding fails
    func decodeError<T: Decodable>(as type: T.Type) -> T? {
        if case .decoded(_, _, let decodedError) = self,
           let typed = decodedError as? T {
            return typed
        }

        return body.decode(as: type)
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

    /// Header field names excluded from `debugDescription` and `description` - present in
    /// `headers` for consumers who deliberately want them, but not in the string a consumer
    /// is likely to paste into a log line or a crash/bug report attachment.
    private static let redactedHeaderNames: Set<String> = [
        "set-cookie",
        "authorization",
        "proxy-authorization"
    ]

    /// A comprehensive debug description including error type, status code, headers, and body preview.
    ///
    /// Provides all relevant error information in a single formatted string, useful for logging.
    /// The response body is truncated to 200 characters to prevent excessive log output.
    /// Excludes `Set-Cookie`, `Authorization`, and `Proxy-Authorization` headers - read
    /// `headers` directly if you need those values.
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

        // Headers, with sensitive header values redacted
        if let headers = headers, !headers.isEmpty {
            let redactedHeaders = headers.filter { !Self.redactedHeaderNames.contains($0.key.lowercased()) }
            if !redactedHeaders.isEmpty {
                let headerStrings = redactedHeaders.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                components.append("Headers: [\(headerStrings)]")
            }
        }

        // Body preview (first 200 characters)
        if let body = responseBodyString {
            let preview = body.prefix(200)
            let suffix = body.count > 200 ? "..." : ""
            components.append("Body: \(preview)\(suffix)")
        }

        return components.joined(separator: " | ")
    }

    /// Equivalent to `debugDescription`, so plain `"\(error)"` string interpolation is also
    /// safe rather than falling back to the enum's synthesized description, which would
    /// expose the unredacted `HTTPResponseSnapshot` associated value.
    var description: String { debugDescription }

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
