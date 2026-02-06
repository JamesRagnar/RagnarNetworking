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

    public let statusCode: Int?

    public let headers: [String: String]

    public let url: URL?

    public let mimeType: String?

    public let expectedContentLength: Int64

    public let textEncodingName: String?

    public init(response: URLResponse) {
        let httpResponse = response as? HTTPURLResponse
        self.statusCode = httpResponse?.statusCode
        let rawHeaders = httpResponse?.allHeaderFields ?? [:]
        var coercedHeaders: [String: String] = [:]
        coercedHeaders.reserveCapacity(rawHeaders.count)
        for (key, value) in rawHeaders {
            coercedHeaders[String(describing: key)] = String(describing: value)
        }
        self.headers = coercedHeaders
        self.url = response.url
        self.mimeType = response.mimeType
        self.expectedContentLength = response.expectedContentLength
        self.textEncodingName = response.textEncodingName
    }

}
