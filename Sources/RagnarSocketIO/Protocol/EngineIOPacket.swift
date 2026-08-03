import Foundation

enum EngineIOPacket: Sendable, Equatable {
    case open(EngineIOOpenPayload)
    case close
    case ping(String)
    case pong(String)
    case message(String)
    case upgrade
    case noop

    func validateMessageSize(maximum: Int) throws {
        guard case .message(let payload) = self else { return }
        let actual = payload.utf8.count
        guard actual <= maximum else {
            throw SocketIOProtocolError.messageExceedsMaximumPayload(limit: maximum, actual: actual)
        }
    }
}
