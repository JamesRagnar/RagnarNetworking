//
//  InterfaceResponse.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// Builds an Interface's `Response` value from a response.
///
/// A `Decodable` type conforms without implementing anything and decodes JSON using the
/// configured `ResponseDecoder`:
///
/// ```swift
/// struct User: Codable, InterfaceResponse {
///     let id: Int
///     let name: String
/// }
/// ```
///
/// Conform directly when a response is not JSON, or when building the value needs the status
/// code or headers. The package ships conformances for `String` (UTF-8), `Data` (raw bytes),
/// `EmptyResponse` (no body), the `Decodable` scalars, `Optional`, and top-level
/// `Array`/`Dictionary`.
///
/// - Note: This protocol does not refine `Sendable`. `Interface.Response` requires
///   `InterfaceResponse & Sendable`, which is what enforces it. Refining it here would compile
///   but grant `Sendable` to `[T]` for non-`Sendable` `T`, because a conditional conformance
///   cannot mention a marker protocol. See `Documentation/Interfaces/response_handling.md`.
public protocol InterfaceResponse {

    /// Builds the response value.
    ///
    /// - Parameters:
    ///   - data: The raw response bytes. Empty for `.noContent` outcomes.
    ///   - metadata: Status code, headers, and URL, already redacted. Use for responses whose
    ///     value depends on a header, such as `ETag` or `Link` pagination.
    ///   - decoder: The decoder configured for this response.
    /// - Throws: Any error type. `DefaultResponseHandler` maps `DecodingError` to
    ///   `InterfaceDecodingError.jsonDecoder` and anything else to `.custom`.
    static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> Self

}

// MARK: - Decodable Default

public extension InterfaceResponse where Self: Decodable {

    /// Decodes JSON using the configured `ResponseDecoder`, ignoring the response metadata.
    static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> Self {
        try decoder.makeJSONDecoder().decode(
            Self.self,
            from: data
        )
    }

}

// MARK: - Built-in Conformances

/// Returns the response bytes decoded as UTF-8.
extension String: InterfaceResponse {

    public static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> String {
        guard let string = String(
            data: data,
            encoding: .utf8
        ) else {
            throw InterfaceDecodingError.missingString
        }

        return string
    }

}

/// Returns the response bytes unchanged, for downloads, streams, and no-body fallbacks.
extension Data: InterfaceResponse {

    public static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> Data {
        data
    }

}

/// Decodes a top-level JSON array, using the default `Decodable` behavior.
extension Array: InterfaceResponse where Element: Decodable {}

/// Decodes a top-level JSON collection, using the stdlib's `Dictionary: Decodable` behavior.
///
/// - Important: That behavior depends on the key type. `String` keys, `Int` keys, and keys
///   conforming to `CodingKeyRepresentable` decode from a JSON object. Any other key type
///   decodes from an alternating unkeyed array (`["a", 1, "b", 2]`) and throws against an
///   object body. Conform the key type to `CodingKeyRepresentable` if the server sends an
///   object.
extension Dictionary: InterfaceResponse where Key: Decodable, Value: Decodable {}

/// Decodes a top-level JSON `null` or value, using the default `Decodable` behavior.
extension Optional: InterfaceResponse where Wrapped: Decodable {}

extension Int: InterfaceResponse {}

extension Int64: InterfaceResponse {}

extension Double: InterfaceResponse {}

extension Bool: InterfaceResponse {}
