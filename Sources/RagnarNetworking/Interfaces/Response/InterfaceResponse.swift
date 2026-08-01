//
//  InterfaceResponse.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// Protocol that all Interface response types must conform to.
///
/// A response type owns how it is built from a response, mirroring the way `RequestBody` owns
/// how a request body is encoded. The alternative - the handler comparing `Response.self`
/// against a fixed list of known types - is closed to extension and pushes what the compiler
/// already knows into runtime casts.
///
/// Conforming a `Decodable` type requires no implementation; the default decodes JSON with the
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
/// code or headers as well as the bytes. The package ships conformances for `String` (UTF-8),
/// `Data` (raw bytes), `EmptyResponse` (no body), the `Decodable` scalars, `Optional`, and
/// top-level `Array`/`Dictionary`.
///
/// - Note: This protocol does not itself refine `Sendable`; `Interface.Response` requires
///   `InterfaceResponse & Sendable` instead. Refining `Sendable` here compiles, but it is
///   unsound: a conditional conformance cannot depend on a marker protocol, so
///   `extension Array: InterfaceResponse where Element: Decodable` would grant `Sendable` to
///   `[T]` without `Array`'s own conditional `Sendable` ever being checked, laundering a
///   non-`Sendable` element type across a concurrency boundary with no diagnostic. Requiring
///   `Sendable` at the use site forces that check to happen. The guarantee is stronger this
///   way, not merely preserved.
public protocol InterfaceResponse {

    /// Builds the response value from the response.
    ///
    /// - Parameters:
    ///   - data: The raw response bytes. Empty for `.noContent` outcomes.
    ///   - metadata: Status code, headers, and URL for the response the bytes came from,
    ///     already redacted. Present so a response whose value depends on a header - `ETag`,
    ///     `Link` pagination, `X-Total-Count`, `Content-Range` - can be built here rather than
    ///     requiring a whole `ResponseHandler`.
    ///   - decoder: The decoder configured for this response.
    /// - Throws: Any error. `DefaultResponseHandler` maps `DecodingError` to
    ///   `InterfaceDecodingError.jsonDecoder` and anything else to `.custom`, so a conformance
    ///   is free to throw its own error type rather than laundering it through this package's.
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

/// Decodes a top-level JSON collection, using the stdlib's `Dictionary: Decodable` behavior
/// verbatim.
///
/// - Important: That behavior depends on the key type. `String` and `Int` keys, and keys
///   conforming to `CodingKeyRepresentable`, decode from a JSON **object**. Any other key type
///   decodes from an **alternating unkeyed array** (`["a", 1, "b", 2]`), not an object, and
///   throws against an object body. Conform the key type to `CodingKeyRepresentable` if the
///   server sends an object.
extension Dictionary: InterfaceResponse where Key: Decodable, Value: Decodable {}

/// Decodes a top-level JSON `null` or value, using the default `Decodable` behavior.
extension Optional: InterfaceResponse where Wrapped: Decodable {}

extension Int: InterfaceResponse {}

extension Int64: InterfaceResponse {}

extension Double: InterfaceResponse {}

extension Bool: InterfaceResponse {}
