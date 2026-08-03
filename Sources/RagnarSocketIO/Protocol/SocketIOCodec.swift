import Foundation

enum SocketIOCodec {
    static func decode(_ payload: String) throws -> SocketIOPacket {
        guard let packetType = payload.first else {
            throw SocketIOProtocolError.missingSocketIOPacketType
        }
        guard "0123456".contains(packetType) else {
            throw SocketIOProtocolError.unknownSocketIOPacketType(String(packetType))
        }

        var remainder = payload.dropFirst()
        let attachmentCount: Int?
        if packetType == "5" || packetType == "6" {
            attachmentCount = try parseAttachmentCount(from: &remainder)
        } else {
            attachmentCount = nil
        }

        let namespace = try parseNamespace(from: &remainder)
        let acknowledgementID = try parseAcknowledgementID(from: &remainder)
        let jsonPayload = String(remainder)

        return try decodePacket(
            type: packetType,
            namespace: namespace,
            acknowledgementID: acknowledgementID,
            attachmentCount: attachmentCount,
            jsonPayload: jsonPayload
        )
    }

    private static func decodePacket(
        type packetType: Character,
        namespace: String,
        acknowledgementID: Int?,
        attachmentCount: Int?,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        switch packetType {
        case "0":
            return try decodeConnect(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                jsonPayload: jsonPayload
            )

        case "1":
            return try decodeDisconnect(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                jsonPayload: jsonPayload
            )

        case "2":
            return try decodeEventPacket(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                jsonPayload: jsonPayload
            )

        case "3":
            return try decodeAcknowledgement(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                jsonPayload: jsonPayload
            )

        case "4":
            return try decodeConnectError(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                jsonPayload: jsonPayload
            )

        case "5":
            return try decodeBinaryEvent(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                attachmentCount: try requiredAttachmentCount(attachmentCount),
                jsonPayload: jsonPayload
            )

        case "6":
            return try decodeBinaryAcknowledgement(
                namespace: namespace,
                acknowledgementID: acknowledgementID,
                attachmentCount: try requiredAttachmentCount(attachmentCount),
                jsonPayload: jsonPayload
            )

        default:
            preconditionFailure("Validated Socket.IO packet type was not handled")
        }
    }
}

extension SocketIOCodec {
    static func encode(_ packet: SocketIOPacket) throws -> String {
        switch packet {
        case .connect(let namespace, let payload):
            let prefix = try "0" + encode(namespace: namespace)
            guard let payload else { return prefix }
            guard try payload.jsonObject() is [String: Any] else {
                throw SocketIOProtocolError.invalidConnectPayload
            }
            return try prefix + text(for: payload)

        case .disconnect(let namespace):
            return try "1" + encode(namespace: namespace)

        case .event(let namespace, let acknowledgementID, let name, let arguments):
            return try "2" + encode(namespace: namespace)
                + encode(acknowledgementID: acknowledgementID)
                + encodeEvent(name: name, arguments: arguments)

        case .acknowledgement(let namespace, let acknowledgementID, let arguments):
            return try "3" + encode(namespace: namespace)
                + String(acknowledgementID)
                + encode(arguments: arguments)

        case .connectError(let namespace, let payload):
            guard try payload.jsonObject() is [String: Any] else {
                throw SocketIOProtocolError.invalidConnectErrorPayload
            }
            return try "4" + encode(namespace: namespace) + text(for: payload)

        case .binaryEvent(
            let namespace,
            let acknowledgementID,
            let attachmentCount,
            let name,
            let arguments
        ):
            return try "5" + encode(attachmentCount: attachmentCount)
                + encode(namespace: namespace)
                + encode(acknowledgementID: acknowledgementID)
                + encodeEvent(name: name, arguments: arguments)

        case .binaryAcknowledgement(let namespace, let acknowledgementID, let attachmentCount, let arguments):
            return try "6" + encode(attachmentCount: attachmentCount)
                + encode(namespace: namespace)
                + String(acknowledgementID)
                + encode(arguments: arguments)
        }
    }
}

private extension SocketIOCodec {
    private static func decodeConnect(
        namespace: String,
        acknowledgementID: Int?,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        guard acknowledgementID == nil else {
            throw SocketIOProtocolError.unexpectedPayload
        }
        return .connect(namespace: namespace, payload: try decodeOptionalObject(jsonPayload))
    }

    private static func decodeDisconnect(
        namespace: String,
        acknowledgementID: Int?,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        guard acknowledgementID == nil, jsonPayload.isEmpty else {
            throw SocketIOProtocolError.unexpectedPayload
        }
        return .disconnect(namespace: namespace)
    }

    private static func decodeEventPacket(
        namespace: String,
        acknowledgementID: Int?,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        let event = try decodeEvent(jsonPayload)
        return .event(
            namespace: namespace,
            acknowledgementID: acknowledgementID,
            name: event.name,
            arguments: event.arguments
        )
    }

    private static func decodeAcknowledgement(
        namespace: String,
        acknowledgementID: Int?,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        guard let acknowledgementID else {
            throw SocketIOProtocolError.missingAcknowledgementID
        }
        return .acknowledgement(
            namespace: namespace,
            acknowledgementID: acknowledgementID,
            arguments: try decodeArguments(jsonPayload)
        )
    }

    private static func decodeConnectError(
        namespace: String,
        acknowledgementID: Int?,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        guard acknowledgementID == nil, !jsonPayload.isEmpty else {
            throw SocketIOProtocolError.invalidConnectErrorPayload
        }
        let argument = try SocketIOArgument(validating: Data(jsonPayload.utf8))
        guard try argument.jsonObject() is [String: Any] else {
            throw SocketIOProtocolError.invalidConnectErrorPayload
        }
        return .connectError(namespace: namespace, payload: argument)
    }

    private static func decodeBinaryEvent(
        namespace: String,
        acknowledgementID: Int?,
        attachmentCount: Int,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        let event = try decodeEvent(jsonPayload)
        return .binaryEvent(
            namespace: namespace,
            acknowledgementID: acknowledgementID,
            attachmentCount: attachmentCount,
            name: event.name,
            arguments: event.arguments
        )
    }

    private static func decodeBinaryAcknowledgement(
        namespace: String,
        acknowledgementID: Int?,
        attachmentCount: Int,
        jsonPayload: String
    ) throws -> SocketIOPacket {
        guard let acknowledgementID else {
            throw SocketIOProtocolError.missingAcknowledgementID
        }
        return .binaryAcknowledgement(
            namespace: namespace,
            acknowledgementID: acknowledgementID,
            attachmentCount: attachmentCount,
            arguments: try decodeArguments(jsonPayload)
        )
    }

    private static func parseAttachmentCount(from remainder: inout Substring) throws -> Int {
        let digits = remainder.prefix(while: \.isNumber)
        guard
            !digits.isEmpty,
            remainder.dropFirst(digits.count).first == "-",
            let count = Int(digits),
            count > 0
        else {
            throw SocketIOProtocolError.invalidBinaryAttachmentCount
        }
        remainder = remainder.dropFirst(digits.count + 1)
        return count
    }

    private static func parseNamespace(from remainder: inout Substring) throws -> String {
        guard remainder.first == "/" else { return "/" }
        guard let comma = remainder.firstIndex(of: ",") else {
            throw SocketIOProtocolError.namespaceMissingComma
        }
        let namespace = String(remainder[..<comma])
        guard namespace.count > 1 else {
            throw SocketIOProtocolError.invalidNamespace
        }
        remainder = remainder[remainder.index(after: comma)...]
        return namespace
    }

    private static func parseAcknowledgementID(from remainder: inout Substring) throws -> Int? {
        let digits = remainder.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        guard let identifier = Int(digits) else {
            throw SocketIOProtocolError.invalidAcknowledgementID
        }
        remainder = remainder.dropFirst(digits.count)
        return identifier
    }

    private static func decodeOptionalObject(_ payload: String) throws -> SocketIOArgument? {
        guard !payload.isEmpty else { return nil }
        let argument = try SocketIOArgument(validating: Data(payload.utf8))
        guard try argument.jsonObject() is [String: Any] else {
            throw SocketIOProtocolError.invalidConnectPayload
        }
        return argument
    }

    private static func decodeEvent(_ payload: String) throws -> (name: String, arguments: [SocketIOArgument]) {
        let objects = try decodeJSONArray(payload, error: .invalidEventPayload)
        guard let name = objects.first as? String else {
            throw SocketIOProtocolError.missingEventName
        }
        return (name, try objects.dropFirst().map(SocketIOArgument.init(jsonObject:)))
    }

    private static func decodeArguments(_ payload: String) throws -> [SocketIOArgument] {
        try decodeJSONArray(payload, error: .invalidJSON).map(SocketIOArgument.init(jsonObject:))
    }

    private static func decodeJSONArray(
        _ payload: String,
        error: SocketIOProtocolError
    ) throws -> [Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(payload.utf8), options: [])
        } catch {
            throw SocketIOProtocolError.invalidJSON
        }
        guard let array = object as? [Any] else { throw error }
        return array
    }
}

private extension SocketIOCodec {
    private static func encode(namespace: String) throws -> String {
        guard namespace == "/" || namespace.first == "/" && !namespace.contains(",") else {
            throw SocketIOProtocolError.invalidNamespace
        }
        return namespace == "/" ? "" : namespace + ","
    }

    private static func encode(acknowledgementID: Int?) -> String {
        acknowledgementID.map(String.init) ?? ""
    }

    private static func encode(attachmentCount: Int) throws -> String {
        guard attachmentCount > 0 else {
            throw SocketIOProtocolError.invalidBinaryAttachmentCount
        }
        return "\(attachmentCount)-"
    }

    private static func encodeEvent(name: String, arguments: [SocketIOArgument]) throws -> String {
        try encode(objects: [name] + arguments.map { try $0.jsonObject() })
    }

    private static func encode(arguments: [SocketIOArgument]) throws -> String {
        try encode(objects: arguments.map { try $0.jsonObject() })
    }

    private static func encode(objects: [Any]) throws -> String {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
        } catch {
            throw SocketIOProtocolError.invalidJSON
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SocketIOProtocolError.invalidJSON
        }
        return text
    }

    private static func text(for argument: SocketIOArgument) throws -> String {
        guard let text = String(data: argument.data, encoding: .utf8) else {
            throw SocketIOProtocolError.invalidJSON
        }
        return text
    }

    private static func requiredAttachmentCount(_ count: Int?) throws -> Int {
        guard let count else {
            throw SocketIOProtocolError.invalidBinaryAttachmentCount
        }
        return count
    }
}
