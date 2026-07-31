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
