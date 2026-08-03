import Foundation

public protocol SocketEvent: Sendable {
    associatedtype Schema: Decodable & Sendable

    static var name: String { get }
    static var defaultStreamPolicy: SocketStreamPolicy { get }

    static func decode(
        arguments: [SocketIOArgument],
        using decoder: JSONDecoder
    ) throws -> Schema
}

public protocol EmittableSocketEvent: SocketEvent {
    static func encode(
        _ value: Schema,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument]
}

public extension SocketEvent {
    static var defaultStreamPolicy: SocketStreamPolicy { .lossless }

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
    static func encode(
        _ value: Schema,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument] {
        [try SocketIOArgument(value, using: encoder)]
    }
}

public extension EmittableSocketEvent where Schema == SocketEmptyBody {
    static func encode(
        _ value: SocketEmptyBody,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument] {
        []
    }
}
