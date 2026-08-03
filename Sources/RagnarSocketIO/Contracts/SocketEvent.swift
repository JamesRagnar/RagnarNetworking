import Foundation

/// A typed incoming Socket.IO event contract.
public protocol SocketEvent: Sendable {
    /// The value produced for one received event.
    associatedtype Schema: Decodable & Sendable

    /// The event name used on the wire.
    static var name: String { get }
    /// The buffering and overflow behavior used by `SocketClient.events(for:)`.
    static var defaultStreamPolicy: SocketStreamPolicy { get }

    /// Decodes the ordered JSON arguments for one event occurrence.
    static func decode(
        arguments: [SocketIOArgument],
        using decoder: JSONDecoder
    ) throws -> Schema
}

/// A Socket.IO event contract that may also be emitted by the client.
public protocol EmittableSocketEvent: SocketEvent {
    /// Encodes a value as the ordered JSON arguments for one event occurrence.
    static func encode(
        _ value: Schema,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument]
}

public extension SocketEvent {
    /// A bounded 64-event lossless policy.
    static var defaultStreamPolicy: SocketStreamPolicy { .lossless }

    /// Decodes exactly one argument as `Schema`.
    static func decode(
        arguments: [SocketIOArgument],
        using decoder: JSONDecoder
    ) throws -> Schema {
        guard arguments.count == 1, let argument = arguments.first else {
            throw SocketIOError.invalidArgumentCount(
                eventName: name,
                expected: 1,
                actual: arguments.count
            )
        }
        return try argument.decode(Schema.self, using: decoder)
    }
}

public extension SocketEvent where Schema == SocketEmptyBody {
    /// Accepts zero arguments or one JSON `null` argument.
    static func decode(
        arguments: [SocketIOArgument],
        using decoder: JSONDecoder
    ) throws -> SocketEmptyBody {
        guard arguments.isEmpty || arguments.count == 1 && arguments[0].isNull else {
            throw SocketIOError.invalidArgumentCount(
                eventName: name,
                expected: 0,
                actual: arguments.count
            )
        }
        return SocketEmptyBody()
    }
}

public extension EmittableSocketEvent where Schema: Encodable {
    /// Encodes `value` as one JSON argument.
    static func encode(
        _ value: Schema,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument] {
        [try SocketIOArgument(value, using: encoder)]
    }
}

public extension EmittableSocketEvent where Schema == SocketEmptyBody {
    /// Encodes an event with zero arguments.
    static func encode(
        _ value: SocketEmptyBody,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument] {
        []
    }
}
