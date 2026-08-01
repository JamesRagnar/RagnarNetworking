//
//  InterfaceResponse.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// Protocol that all Interface response types must conform to.
///
/// A response type owns how it is built from response bytes, mirroring the way `RequestBody`
/// owns how a request body is encoded. The alternative - the handler comparing `Response.self`
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
/// Conform directly when a response is not JSON. The package ships conformances for `String`
/// (UTF-8), `Data` (raw bytes), `EmptyResponse` (no body), and top-level `Array`/`Dictionary`.
///
/// - Note: This protocol does not itself refine `Sendable`; `Interface.Response` requires
///   `InterfaceResponse & Sendable` instead. Swift forbids a conditional conformance from
///   depending on a marker protocol, so refining `Sendable` here would make the
///   `Array`/`Dictionary` conformances inexpressible. The guarantee is unchanged at the only
///   place it matters.
public protocol InterfaceResponse {

    /// Builds the response value from raw response bytes.
    ///
    /// - Parameters:
    ///   - data: The raw response bytes. Empty for `.noContent` outcomes.
    ///   - decoder: The decoder configured for this response.
    /// - Throws: Any error. `DefaultResponseHandler` maps `DecodingError` to
    ///   `InterfaceDecodingError.jsonDecoder` and anything else to `.custom`, so a conformance
    ///   is free to throw its own error type rather than laundering it through this package's.
    static func decode(
        from data: Data,
        using decoder: ResponseDecoder
    ) throws -> Self

}

// MARK: - Decodable Default

public extension InterfaceResponse where Self: Decodable {

    /// Decodes JSON using the configured `ResponseDecoder`.
    static func decode(
        from data: Data,
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
        using decoder: ResponseDecoder
    ) throws -> Data {
        data
    }

}

/// Decodes a top-level JSON array, using the default `Decodable` behavior.
extension Array: InterfaceResponse where Element: Decodable {}

/// Decodes a top-level JSON object as a dictionary, using the default `Decodable` behavior.
extension Dictionary: InterfaceResponse where Key: Decodable, Value: Decodable {}
