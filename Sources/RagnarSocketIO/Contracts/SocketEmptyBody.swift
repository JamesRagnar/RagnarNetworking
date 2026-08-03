import Foundation

/// The schema for a Socket.IO event that carries no arguments.
public struct SocketEmptyBody: Codable, Sendable, Equatable {
    /// Creates an empty event value.
    public init() {}

    /// Decodes a JSON `null` value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "SocketEmptyBody requires JSON null."
            )
        }
    }

    /// Encodes a JSON `null` value when used outside the event contract's zero-argument specialization.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
