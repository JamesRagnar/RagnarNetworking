//
//  RequestEncoder.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-03.
//

import Foundation

/// Configuration for request body encoding.
/// Uses a factory pattern to maintain Sendable conformance
public struct RequestEncoder: Sendable {

    /// Factory that creates a configured JSONEncoder.
    /// Called per-request to ensure thread safety.
    public let makeJSONEncoder: @Sendable () -> JSONEncoder

    /// Creates a RequestEncoder with default JSONEncoder settings.
    public init() {
        self.makeJSONEncoder = { JSONEncoder() }
    }

    /// Creates a RequestEncoder with custom encoder factory.
    ///
    /// - Parameter makeJSONEncoder: Factory closure that creates configured encoders.
    public init(makeJSONEncoder: @escaping @Sendable () -> JSONEncoder) {
        self.makeJSONEncoder = makeJSONEncoder
    }

    /// Convenience initializer for common configurations.
    ///
    /// - Parameters:
    ///   - keyEncodingStrategy: Key encoding strategy (default: .useDefaultKeys)
    ///   - dateEncodingStrategy: Date encoding strategy (default: .deferredToDate)
    ///   - outputFormatting: Output formatting options (default: [])
    public init(
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
        outputFormatting: JSONEncoder.OutputFormatting = []
    ) {
        self.makeJSONEncoder = {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = keyEncodingStrategy
            encoder.dateEncodingStrategy = dateEncodingStrategy
            encoder.outputFormatting = outputFormatting
            return encoder
        }
    }

}
