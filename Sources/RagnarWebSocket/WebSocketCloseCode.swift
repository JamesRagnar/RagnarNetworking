import Foundation

public enum WebSocketCloseCode: Int, Sendable {
    case normalClosure = 1000
    case goingAway = 1001
    case protocolError = 1002
    case unsupportedData = 1003
    case invalidFramePayloadData = 1007
    case policyViolation = 1008
    case messageTooBig = 1009
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
