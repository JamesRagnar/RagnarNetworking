import Foundation

/// A Sendable summary of an event schema decoding failure.
public struct SocketIODecodingErrorSnapshot: Sendable, Equatable {
    /// The decoding error category or fully qualified error type name.
    public let category: String
    /// The coding path at which decoding failed.
    public let codingPath: [String]

    /// Captures a decoding error without retaining the underlying error value.
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

/// Errors reported by typed Socket.IO event operations.
public enum SocketIOError: Error, Sendable, Equatable {
    /// A bounded stream policy used a nonpositive capacity.
    case invalidStreamCapacity(Int)
    /// An event received a different number of arguments than its contract requires.
    case invalidArgumentCount(eventName: String, expected: Int, actual: Int)
    /// An event argument could not be decoded as its schema.
    case eventDecodingFailed(eventName: String, snapshot: SocketIODecodingErrorSnapshot)
    /// A terminating stream policy dropped an event because its buffer was full.
    case bufferOverflow(eventName: String)
    /// An emission was attempted before the default namespace connected.
    case notConnected
    /// An emitted Engine.IO message exceeds the server's handshake limit.
    case messageTooLarge(limit: Int, actual: Int)
    /// The operation was attempted after permanent client invalidation.
    case invalidated
}

extension SocketIOError: LocalizedError {
    /// A description of the failed typed event operation.
    public var errorDescription: String? {
        switch self {
        case .invalidStreamCapacity(let capacity):
            "Socket event stream capacity must be positive, not \(capacity)."

        case .invalidArgumentCount(let eventName, let expected, let actual):
            "Socket event \(eventName) expected \(expected) arguments but received \(actual)."

        case .eventDecodingFailed(let eventName, let snapshot):
            "Socket event \(eventName) failed decoding with \(snapshot.category)."

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
