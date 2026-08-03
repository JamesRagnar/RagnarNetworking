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
        let actual = try EngineIOCodec.encode(self).utf8.count
        guard actual <= maximum else {
            throw SocketIOProtocolError.messageExceedsMaximumPayload(limit: maximum, actual: actual)
        }
    }
}
