//
//  ResponseDecoder.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-03.
//

import Foundation

/// Configuration for response body decoding.
/// Uses a factory pattern to maintain Sendable conformance.
public struct ResponseDecoder: Sendable {

    /// Factory that creates a configured JSONDecoder.
    /// Called per-response to ensure thread safety.
    public let makeJSONDecoder: @Sendable () -> JSONDecoder

    /// Creates a ResponseDecoder with default JSONDecoder settings.
    public init() {
        self.makeJSONDecoder = { JSONDecoder() }
    }

    /// Creates a ResponseDecoder with custom decoder factory.
    ///
    /// - Parameter makeJSONDecoder: Factory closure that creates configured decoders.
    public init(makeJSONDecoder: @escaping @Sendable () -> JSONDecoder) {
        self.makeJSONDecoder = makeJSONDecoder
    }

    /// Convenience initializer for common configurations.
    ///
    /// - Parameters:
    ///   - keyDecodingStrategy: Key decoding strategy (default: .useDefaultKeys)
    ///   - dateDecodingStrategy: Date decoding strategy (default: .deferredToDate)
    public init(
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate
    ) {
        self.makeJSONDecoder = {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = keyDecodingStrategy
            decoder.dateDecodingStrategy = dateDecodingStrategy
            return decoder
        }
    }

}

// MARK: - Deriving and Decoding

public extension ResponseDecoder {

    /// A copy of this configuration with `configure` applied to each decoder it produces, after
    /// this configuration's own setup has run.
    ///
    /// Use from an `InterfaceResponse` conformance to override one strategy while keeping the
    /// client's other rules. Building a bare `JSONDecoder()` there instead would silently drop
    /// them.
    ///
    /// ```swift
    /// try decoder
    ///     .modified { $0.dateDecodingStrategy = .secondsSince1970 }
    ///     .decode(LegacyOrder.self, from: data)
    /// ```
    func modified(
        _ configure: @escaping @Sendable (JSONDecoder) -> Void
    ) -> ResponseDecoder {
        let base = makeJSONDecoder

        return ResponseDecoder {
            let decoder = base()
            configure(decoder)
            return decoder
        }
    }

    /// Decodes `type` from `data` using a decoder from this configuration.
    func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        try makeJSONDecoder().decode(
            type,
            from: data
        )
    }

}
