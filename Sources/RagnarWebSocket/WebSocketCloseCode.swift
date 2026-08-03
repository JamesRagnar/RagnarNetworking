import Foundation

/// Close codes that may be sent by `WebSocketClient.close(code:reason:)`.
public enum WebSocketCloseCode: Int, Sendable {
    /// The connection fulfilled its purpose.
    case normalClosure = 1000
    /// The endpoint is leaving and does not expect the connection to continue.
    case goingAway = 1001
    /// The endpoint received data that violates the protocol.
    case protocolError = 1002
    /// The endpoint received a message type it cannot accept.
    case unsupportedData = 1003
    /// The endpoint received inconsistent or invalid message data.
    case invalidFramePayloadData = 1007
    /// The endpoint received a message that violates its policy.
    case policyViolation = 1008
    /// The endpoint received a message that exceeds its size limit.
    case messageTooBig = 1009
    /// The endpoint could not complete the request because of an internal error.
    case internalServerError = 1011
}

extension WebSocketCloseCode {
    var foundationValue: URLSessionWebSocketTask.CloseCode {
        switch self {
        case .normalClosure:
            .normalClosure

        case .goingAway:
            .goingAway

        case .protocolError:
            .protocolError

        case .unsupportedData:
            .unsupportedData

        case .invalidFramePayloadData:
            .invalidFramePayloadData

        case .policyViolation:
            .policyViolation

        case .messageTooBig:
            .messageTooBig

        case .internalServerError:
            .internalServerError
        }
    }
}
