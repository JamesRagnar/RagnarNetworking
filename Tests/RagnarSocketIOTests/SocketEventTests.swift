import Foundation
@testable import RagnarSocketIO
import Testing

private enum ValueEvent<Value: Codable & Sendable>: SocketEvent {
    typealias Schema = Value
    static var name: String { "value" }
}

private enum EmptyEvent: EmittableSocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "empty"
}

private enum ObjectEvent: EmittableSocketEvent {
    struct Schema: Codable, Sendable, Equatable {
        let firstValue: Int
    }

    static let name = "object"
}

private enum MultiArgumentEvent: EmittableSocketEvent {
    struct Schema: Codable, Sendable, Equatable {
        let identifier: Int
        let name: String
    }

    static let name = "multi"

    static func decode(
        arguments: [SocketIOArgument],
        using decoder: JSONDecoder
    ) throws -> Schema {
        guard arguments.count == 2 else {
            throw SocketIOError.invalidArgumentCount(eventName: name, expected: 2, actual: arguments.count)
        }
        return try Schema(
            identifier: arguments[0].decode(Int.self, using: decoder),
            name: arguments[1].decode(String.self, using: decoder)
        )
    }

    static func encode(
        _ value: Schema,
        using encoder: JSONEncoder
    ) throws -> [SocketIOArgument] {
        [
            try SocketIOArgument(value.identifier, using: encoder),
            try SocketIOArgument(value.name, using: encoder)
        ]
    }
}

@Suite("Socket Event Contracts")
struct SocketEventTests {
    @Test("Default decoding supports JSON value shapes")
    func valueShapes() throws {
        #expect(try ValueEvent<Int>.decode(arguments: [SocketIOArgument(1)], using: JSONDecoder()) == 1)
        #expect(try ValueEvent<String>.decode(arguments: [SocketIOArgument("value")], using: JSONDecoder()) == "value")
        #expect(try ValueEvent<Bool>.decode(arguments: [SocketIOArgument(true)], using: JSONDecoder()))
        #expect(try ValueEvent<[Int]>.decode(arguments: [SocketIOArgument([1, 2])], using: JSONDecoder()) == [1, 2])
        #expect(
            try ValueEvent<[String: Int]>.decode(
                arguments: [SocketIOArgument(["value": 1])],
                using: JSONDecoder()
            ) == ["value": 1]
        )
        #expect(
            try ValueEvent<Int?>.decode(arguments: [.null], using: JSONDecoder()) == nil
        )
    }

    @Test("Default decoding requires one argument")
    func argumentCount() {
        #expect(throws: SocketIOError.invalidArgumentCount(eventName: "value", expected: 1, actual: 0)) {
            try ValueEvent<Int>.decode(arguments: [], using: JSONDecoder())
        }
        #expect(throws: SocketIOError.invalidArgumentCount(eventName: "value", expected: 1, actual: 2)) {
            try ValueEvent<Int>.decode(arguments: [SocketIOArgument(1), SocketIOArgument(2)], using: JSONDecoder())
        }
    }

    @Test("Empty events accept zero arguments or one null")
    func emptyEvent() throws {
        #expect(try EmptyEvent.decode(arguments: [], using: JSONDecoder()) == SocketEmptyBody())
        #expect(try EmptyEvent.decode(arguments: [.null], using: JSONDecoder()) == SocketEmptyBody())
        #expect(try EmptyEvent.encode(SocketEmptyBody(), using: JSONEncoder()).isEmpty)
        #expect(throws: SocketIOError.self) {
            try EmptyEvent.decode(arguments: [SocketIOArgument(1)], using: JSONDecoder())
        }
    }

    @Test("Default and custom emission preserve argument boundaries")
    func emission() throws {
        let object = ObjectEvent.Schema(firstValue: 1)
        let encodedObject = try ObjectEvent.encode(object, using: JSONEncoder())
        #expect(encodedObject.count == 1)
        #expect(try encodedObject[0].decode(ObjectEvent.Schema.self) == object)

        let multi = MultiArgumentEvent.Schema(identifier: 1, name: "name")
        let encodedMulti = try MultiArgumentEvent.encode(multi, using: JSONEncoder())
        #expect(encodedMulti.count == 2)
        #expect(try MultiArgumentEvent.decode(arguments: encodedMulti, using: JSONDecoder()) == multi)
    }

    @Test("Stream policy validates bounded capacity")
    func policyValidation() throws {
        #expect(throws: SocketIOError.invalidStreamCapacity(0)) {
            try SocketStreamPolicy(buffering: .oldest(0), loss: .terminate)
        }
        #expect(throws: SocketIOError.invalidStreamCapacity(-1)) {
            try SocketStreamPolicy(buffering: .newest(-1), loss: .discard)
        }
        #expect(try SocketStreamPolicy.lossless(capacity: 2).buffering == .oldest(2))
        #expect(try SocketStreamPolicy.latest(capacity: 2).buffering == .newest(2))
        #expect(SocketStreamPolicy.unbounded.buffering == .unbounded)
    }

    @Test("Coder factories apply custom strategies")
    func coderFactories() throws {
        struct Schema: Codable, Sendable, Equatable {
            let createdAt: Date
            let firstValue: Int
        }

        let encoder = SocketEventEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return encoder
        }
        let decoder = SocketEventDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
        let value = Schema(createdAt: Date(timeIntervalSince1970: 0), firstValue: 1)
        let argument = try SocketIOArgument(value, using: encoder.makeEncoder())
        #expect(try argument.decode(Schema.self, using: decoder.makeDecoder()) == value)
    }
}
