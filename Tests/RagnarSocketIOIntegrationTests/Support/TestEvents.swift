import Foundation
import RagnarSocketIO

enum FixtureReadyEvent: SocketEvent {
    struct Schema: Codable, Sendable, Equatable {
        let connectionNumber: Int
    }

    static let name = "fixture:ready"
}

enum FixtureEchoEvent<Value: Codable & Sendable>: EmittableSocketEvent {
    typealias Schema = Value
    static var name: String { "fixture:echo" }
}

enum FixtureObjectEchoEvent: EmittableSocketEvent {
    typealias Schema = FixtureObjectEvent.Schema
    static let name = "fixture:echo-object"
}

enum FixtureArrayEchoEvent: EmittableSocketEvent {
    typealias Schema = [Int]
    static let name = "fixture:echo-array"
}

enum FixtureZeroEvent: SocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "fixture:zero"
}

enum FixtureNullEvent: SocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "fixture:null"
}

enum FixtureScalarEvent: SocketEvent {
    typealias Schema = Int
    static let name = "fixture:scalar"
}

enum FixtureObjectEvent: SocketEvent {
    struct Schema: Codable, Sendable, Equatable {
        let value: Int
    }

    static let name = "fixture:object"
}

enum FixtureArrayEvent: SocketEvent {
    typealias Schema = [Int]
    static let name = "fixture:array"
}

enum FixtureMultiEvent: EmittableSocketEvent {
    struct Schema: Codable, Sendable, Equatable {
        let number: Int
        let text: String
    }

    static let name = "fixture:multi"

    static func decode(
        arguments: [SocketIOArgument],
        using decoder: JSONDecoder
    ) throws -> Schema {
        guard arguments.count == 2 else {
            throw FixtureEventError.invalidArgumentCount
        }
        return try Schema(
            number: arguments[0].decode(Int.self, using: decoder),
            text: arguments[1].decode(String.self, using: decoder)
        )
    }

    static func encode(
        _ value: Schema,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument] {
        [
            try SocketIOArgument(value.number, using: encoder),
            try SocketIOArgument(value.text, using: encoder)
        ]
    }
}

enum FixtureCommandEvent: EmittableSocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "fixture:emit-shapes"
}

enum FixtureCloseTransportEvent: EmittableSocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "fixture:close-transport"
}

enum FixtureDisconnectEvent: EmittableSocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "fixture:disconnect-namespace"
}

enum FixtureAcknowledgementEvent: EmittableSocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "fixture:emit-acknowledgement"
}

enum FixtureEventError: Error {
    case invalidArgumentCount
}
