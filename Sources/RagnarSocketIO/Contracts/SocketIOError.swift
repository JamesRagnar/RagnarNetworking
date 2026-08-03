import Foundation

public struct SocketIODecodingErrorSnapshot: Sendable, Equatable {
    public let category: String
    public let codingPath: [String]

    public init(_ error: any Error) {
        switch error {
        case DecodingError.typeMismatch(_, let context):
            category = "typeMismatch"
            codingPath = context.codingPath.map(\.stringValue)

        case DecodingError.valueNotFound(_, let context):
            category = "valueNotFound"
            codingPath = context.codingPath.map(\.stringValue)

        case DecodingError.keyNotFound(let key, let context):
            category = "keyNotFound"
            codingPath = context.codingPath.map(\.stringValue) + [key.stringValue]

        case DecodingError.dataCorrupted(let context):
            category = "dataCorrupted"
            codingPath = context.codingPath.map(\.stringValue)

        default:
            category = String(reflecting: type(of: error))
            codingPath = []
        }
    }
}

public enum SocketIOError: Error, Sendable, Equatable {
    case invalidStreamCapacity(Int)
    case invalidArgumentCount(eventName: String, expected: Int, actual: Int)
    case eventDecodingFailed(eventName: String, snapshot: SocketIODecodingErrorSnapshot)
    case unsupportedBinaryArgument(eventName: String)
    case bufferOverflow(eventName: String)
    case notConnected
    case messageTooLarge(limit: Int, actual: Int)
    case invalidated
}

extension SocketIOError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidStreamCapacity(let capacity):
            "Socket event stream capacity must be positive, not \(capacity)."

        case .invalidArgumentCount(let eventName, let expected, let actual):
            "Socket event \(eventName) expected \(expected) arguments but received \(actual)."

        case .eventDecodingFailed(let eventName, let snapshot):
            "Socket event \(eventName) failed decoding with \(snapshot.category)."

        case .unsupportedBinaryArgument(let eventName):
            "Socket event \(eventName) contains an unsupported binary argument."

        case .bufferOverflow(let eventName):
            "Socket event \(eventName) exceeded its stream buffer."

        case .notConnected:
            "The Socket.IO client is not connected."

        case .messageTooLarge(let limit, let actual):
            "The Socket.IO message contains \(actual) bytes, exceeding the \(limit)-byte limit."

        case .invalidated:
            "The Socket.IO client was invalidated."
        }
    }
}
