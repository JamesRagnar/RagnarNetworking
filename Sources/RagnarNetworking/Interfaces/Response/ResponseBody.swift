//
//  ResponseBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// A response body paired with the decoder that was configured to read it.
///
/// Carrying the decoder alongside the bytes means a `ResponseError` that escapes into
/// application code can still decode its body with the client's own rules. The alternative -
/// asking the catch site to supply a decoder - defaults to plain `JSONDecoder()` and is
/// silently wrong for any client configured with, say, `.convertFromSnakeCase`.
public struct ResponseBody: Sendable {

    /// The raw response bytes.
    public let data: Data

    /// The decoder resolved for the response this body came from.
    public let decoder: ResponseDecoder

    /// Creates a response body.
    /// - Parameters:
    ///   - data: The raw response bytes
    ///   - decoder: The decoder configured for this response. Defaults to a plain decoder,
    ///     which is appropriate only when no configured decoder is in play.
    public init(
        _ data: Data,
        decoder: ResponseDecoder = ResponseDecoder()
    ) {
        self.data = data
        self.decoder = decoder
    }

    /// The body as a UTF-8 string, or `nil` if the bytes are not valid UTF-8.
    public var stringValue: String? {
        String(
            data: data,
            encoding: .utf8
        )
    }

    /// Decodes the body as `type` using the response's own decoder.
    /// - Returns: The decoded value, or `nil` if decoding fails.
    public func decode<T: Decodable>(as type: T.Type) -> T? {
        try? decoder.makeJSONDecoder().decode(type, from: data)
    }

}
