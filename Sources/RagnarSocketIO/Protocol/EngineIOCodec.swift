import Foundation

enum EngineIOCodec {
    static func decode(_ text: String) throws -> EngineIOPacket {
        guard let packetType = text.first else {
            throw SocketIOProtocolError.unknownEngineIOPacketType(nil)
        }

        let payload = String(text.dropFirst())
        switch packetType {
        case "0":
            return .open(try decodeOpen(payload))

        case "1":
            return .close

        case "2":
            return .ping(payload)

        case "3":
            return .pong(payload)

        case "4":
            return .message(payload)

        case "5":
            return .upgrade

        case "6":
            return .noop

        default:
            throw SocketIOProtocolError.unknownEngineIOPacketType(String(packetType))
        }
    }

    static func encode(_ packet: EngineIOPacket) throws -> String {
        switch packet {
        case .open(let payload):
            let data = try JSONEncoder().encode(payload.wireValue)
            guard let text = String(data: data, encoding: .utf8) else {
                throw SocketIOProtocolError.malformedOpenPayload
            }
            return "0" + text

        case .close:
            return "1"

        case .ping(let payload):
            return "2" + payload

        case .pong(let payload):
            return "3" + payload

        case .message(let payload):
            return "4" + payload

        case .upgrade:
            return "5"

        case .noop:
            return "6"
        }
    }

    private static func decodeOpen(_ payload: String) throws -> EngineIOOpenPayload {
        guard let data = payload.data(using: .utf8) else {
            throw SocketIOProtocolError.malformedOpenPayload
        }

        do {
            return try JSONDecoder().decode(EngineIOOpenPayload.self, from: data)
        } catch let error as SocketIOProtocolError {
            throw error
        } catch {
            throw SocketIOProtocolError.malformedOpenPayload
        }
    }
}
