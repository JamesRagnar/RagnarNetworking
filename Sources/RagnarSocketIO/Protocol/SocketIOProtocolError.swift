import Foundation

/// Errors produced while validating or coding the supported Engine.IO and Socket.IO protocol subset.
public enum SocketIOProtocolError: Error, Sendable, Equatable {
    /// An endpoint is missing a supported scheme or host.
    case invalidEndpoint
    /// A complete request does not specify Engine.IO protocol 4 exactly once.
    case unsupportedEngineIOVersion(String?)
    /// A complete request does not specify direct WebSocket transport exactly once.
    case unsupportedTransport(String?)
    /// An Engine.IO packet begins with an unknown or missing packet type.
    case unknownEngineIOPacketType(String?)
    /// An Engine.IO `OPEN` payload is not valid for the required fields.
    case malformedOpenPayload
    /// A heartbeat duration is nonpositive, too large, or not representable in whole milliseconds.
    case invalidHeartbeatTiming
    /// The Engine.IO maximum payload is not positive.
    case invalidMaximumPayload
    /// An outgoing Engine.IO message exceeds the server's maximum payload.
    case messageExceedsMaximumPayload(limit: Int, actual: Int)
    /// A Socket.IO packet has no packet type.
    case missingSocketIOPacketType
    /// A Socket.IO packet begins with an unknown packet type.
    case unknownSocketIOPacketType(String)
    /// A binary packet has a missing, malformed, or nonpositive attachment count.
    case invalidBinaryAttachmentCount
    /// A Socket.IO namespace is malformed.
    case invalidNamespace
    /// A non-default namespace does not end with the required comma.
    case namespaceMissingComma
    /// An acknowledgement identifier cannot be represented as an integer.
    case invalidAcknowledgementID
    /// A packet that requires an acknowledgement identifier does not contain one.
    case missingAcknowledgementID
    /// A packet contains malformed JSON.
    case invalidJSON
    /// An event payload is not a JSON array.
    case invalidEventPayload
    /// An event payload does not begin with a string event name.
    case missingEventName
    /// A `CONNECT` payload is present but is not a JSON object.
    case invalidConnectPayload
    /// A `CONNECT_ERROR` payload is missing or is not a JSON object.
    case invalidConnectErrorPayload
    /// A packet contains fields or payload data that its type does not permit.
    case unexpectedPayload
}

extension SocketIOProtocolError: LocalizedError {
    /// A description of the protocol validation or coding failure.
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The Socket.IO endpoint is invalid."

        case .unsupportedEngineIOVersion(let version):
            "Engine.IO version \(version ?? "missing") is unsupported."

        case .unsupportedTransport(let transport):
            "Engine.IO transport \(transport ?? "missing") is unsupported."

        case .unknownEngineIOPacketType(let packetType):
            "Engine.IO packet type \(packetType ?? "missing") is unknown."

        case .malformedOpenPayload:
            "The Engine.IO open payload is malformed."

        case .invalidHeartbeatTiming:
            "The Engine.IO heartbeat timing is invalid."

        case .invalidMaximumPayload:
            "The Engine.IO maximum payload is invalid."

        case .messageExceedsMaximumPayload(let limit, let actual):
            "The Engine.IO message contains \(actual) bytes, exceeding the \(limit)-byte limit."

        case .missingSocketIOPacketType:
            "The Socket.IO packet type is missing."

        case .unknownSocketIOPacketType(let packetType):
            "Socket.IO packet type \(packetType) is unknown."

        case .invalidBinaryAttachmentCount:
            "The Socket.IO binary attachment count is invalid."

        case .invalidNamespace:
            "The Socket.IO namespace is invalid."

        case .namespaceMissingComma:
            "The Socket.IO namespace is missing its terminating comma."

        case .invalidAcknowledgementID:
            "The Socket.IO acknowledgement identifier is invalid."

        case .missingAcknowledgementID:
            "The Socket.IO acknowledgement identifier is missing."

        case .invalidJSON:
            "The Socket.IO packet contains invalid JSON."

        case .invalidEventPayload:
            "The Socket.IO event payload must be a JSON array."

        case .missingEventName:
            "The Socket.IO event payload must begin with a string name."

        case .invalidConnectPayload:
            "The Socket.IO connect payload must be a JSON object."

        case .invalidConnectErrorPayload:
            "The Socket.IO connect-error payload must be a JSON object."

        case .unexpectedPayload:
            "The Socket.IO packet contains an unexpected payload."
        }
    }
}
