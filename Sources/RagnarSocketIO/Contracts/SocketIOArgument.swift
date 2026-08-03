import Foundation

public struct SocketIOArgument: Sendable, Equatable {
    public static let null = SocketIOArgument(unchecked: Data("null".utf8))

    public let data: Data

    public init<Value: Encodable>(
        _ value: Value,
        using encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(value)
        try self.init(validating: data)
    }

    public func decode<Value: Decodable>(
        _ type: Value.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(type, from: data)
    }

    public var isNull: Bool {
        data == Self.null.data
    }

    init(validating data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SocketIOProtocolError.invalidJSON
        }
        self.data = try Self.data(for: object)
    }

    init(jsonObject: Any) throws {
        data = try Self.data(for: jsonObject)
    }

    func jsonObject() throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SocketIOProtocolError.invalidJSON
        }
    }

    private init(unchecked data: Data) {
        self.data = data
    }

    private static func data(for object: Any) throws -> Data {
        do {
            return try JSONSerialization.data(
                withJSONObject: object,
                options: [.fragmentsAllowed, .sortedKeys]
            )
        } catch {
            throw SocketIOProtocolError.invalidJSON
        }
    }
}
