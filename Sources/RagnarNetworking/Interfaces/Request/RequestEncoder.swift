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

// MARK: - Deriving and Encoding

public extension RequestEncoder {

    /// A copy of this configuration with `configure` applied to each encoder it produces, after
    /// this configuration's own setup has run.
    ///
    /// Use from a `RequestBody` conformance to override one strategy while keeping the client's
    /// other rules. Building a bare `JSONEncoder()` there instead would silently drop them.
    ///
    /// ```swift
    /// try encoder
    ///     .modified { $0.dateEncodingStrategy = .secondsSince1970 }
    ///     .encode(self)
    /// ```
    func modified(
        _ configure: @escaping @Sendable (JSONEncoder) -> Void
    ) -> RequestEncoder {
        let base = makeJSONEncoder

        return RequestEncoder {
            let encoder = base()
            configure(encoder)
            return encoder
        }
    }

    /// Encodes `value` using an encoder from this configuration.
    func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeJSONEncoder().encode(value)
    }

}
