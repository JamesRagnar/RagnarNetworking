//
//  EngineIOFrame.swift
//  RagnarNetworking
//

import Foundation

/// Engine.IO packet types (https://socket.io/docs/v4/engine-io-protocol/#protocol).
enum EngineIOPacketType: Character, Sendable {
    case open = "0"
    case close = "1"
    case ping = "2"
    case pong = "3"
    case message = "4"
    case upgrade = "5"
    case noop = "6"

    /// The single-character wire prefix for this packet type.
    var wireValue: String { String(rawValue) }
}

/// Socket.IO packet types, nested within an Engine.IO `.message` packet
/// (https://socket.io/docs/v4/socket-io-protocol/#packet-types).
enum SocketIOPacketType: Character, Sendable {
    case connect = "0"
    case disconnect = "1"
    case event = "2"
    case ack = "3"
    case connectError = "4"
    case binaryEvent = "5"
    case binaryAck = "6"

    /// The wire prefix for this packet, nested within an Engine.IO `.message` packet.
    var enginePrefixedWireValue: String { EngineIOPacketType.message.wireValue + String(rawValue) }
}

/// An Engine.IO frame decomposed into its packet type, nested Socket.IO packet type
/// (present only when `engineIOType == .message`), and remaining payload text.
struct ParsedEngineIOFrame {
    let engineIOType: EngineIOPacketType
    let socketIOType: SocketIOPacketType?
    let payload: Substring

    /// Parses a raw WebSocket text frame. Returns `nil` if the leading character is not a
    /// recognized Engine.IO packet type. A recognized Engine.IO type whose nested character
    /// is not a recognized Socket.IO packet type still parses, with `socketIOType` `nil` and
    /// the unrecognized character left in `payload` for the caller to log or ignore.
    static func parse(_ text: String) -> ParsedEngineIOFrame? {
        guard let first = text.first, let engineIOType = EngineIOPacketType(rawValue: first) else {
            return nil
        }

        let afterEngineIOType = text.dropFirst()

        guard engineIOType == .message else {
            return ParsedEngineIOFrame(engineIOType: engineIOType, socketIOType: nil, payload: afterEngineIOType)
        }

        guard let second = afterEngineIOType.first, let socketIOType = SocketIOPacketType(rawValue: second) else {
            return ParsedEngineIOFrame(engineIOType: engineIOType, socketIOType: nil, payload: afterEngineIOType)
        }

        return ParsedEngineIOFrame(
            engineIOType: engineIOType,
            socketIOType: socketIOType,
            payload: afterEngineIOType.dropFirst()
        )
    }
}
