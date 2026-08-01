//
//  ResponseBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// A response body paired with the decoder that was configured to read it.
///
/// A `ResponseError` that escapes into application code carries one of these, so `decodeError`
/// at the catch site reads the body with the client's rules rather than a plain `JSONDecoder`.
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
        try? decoder.decode(type, from: data)
    }

}
