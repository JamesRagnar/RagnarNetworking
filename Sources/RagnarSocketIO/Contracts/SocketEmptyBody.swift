import Foundation

public struct SocketEmptyBody: Codable, Sendable, Equatable {
    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "SocketEmptyBody requires JSON null."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
