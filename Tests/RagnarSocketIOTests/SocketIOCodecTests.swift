import Foundation
@testable import RagnarSocketIO
import Testing

private func argument<Value: Encodable>(_ value: Value) throws -> SocketIOArgument {
    try SocketIOArgument(value)
}

@Suite("Socket.IO Codec")
struct SocketIOCodecTests {
    @Test(
        "Every packet type round trips",
        arguments: [
            "0",
            #"0/admin,{"token":"value"}"#,
            "1",
            "1/admin,",
            #"2["empty"]"#,
            #"2["null",null]"#,
            #"2/admin,12["many",1,"two",{"three":3},[4]]"#,
            #"312[1,"two"]"#,
            #"3/admin,12[]"#,
            #"4{"message":"unauthorized"}"#,
            #"4/admin,{"message":"unauthorized"}"#,
            #"51-["binary",{"_placeholder":true,"num":0}]"#,
            #"52-/admin,12["binary",{"_placeholder":true,"num":0},{"_placeholder":true,"num":1}]"#,
            #"61-12[{"_placeholder":true,"num":0}]"#,
            #"61-/admin,12[{"_placeholder":true,"num":0}]"#
        ]
    )
    func roundTrip(text: String) throws {
        let packet = try SocketIOCodec.decode(text)
        let encoded = try SocketIOCodec.encode(packet)
        #expect(try SocketIOCodec.decode(encoded) == packet)
    }

    @Test("Event arguments retain zero, null, scalar, object, array, and multiple shapes")
    func eventArguments() throws {
        let packet = try SocketIOCodec.decode(#"2["event",null,1,"two",{"value":3},[4]]"#)
        guard case .event(let namespace, let acknowledgementID, let name, let arguments) = packet else {
            Issue.record("Expected an event packet")
            return
        }

        #expect(namespace == "/")
        #expect(acknowledgementID == nil)
        #expect(name == "event")
        #expect(arguments.count == 5)
        #expect(arguments[0].isNull)
        #expect(try arguments[1].decode(Int.self) == 1)
        #expect(try arguments[2].decode(String.self) == "two")
        #expect(try arguments[3].decode([String: Int].self) == ["value": 3])
        #expect(try arguments[4].decode([Int].self) == [4])
    }

    @Test("Event names and strings use JSON escaping")
    func escaping() throws {
        let packet = SocketIOPacket.event(
            namespace: "/",
            acknowledgementID: nil,
            name: "quoted\"name",
            arguments: [try argument("line\nbreak")]
        )
        let encoded = try SocketIOCodec.encode(packet)
        #expect(encoded.contains(#"quoted\"name"#))
        #expect(try SocketIOCodec.decode(encoded) == packet)
    }

    @Test("Acknowledgement and binary metadata remain distinct")
    func metadata() throws {
        let packet = try SocketIOCodec.decode(#"52-/admin,19["event",null]"#)
        guard case .binaryEvent(
            let namespace,
            let acknowledgementID,
            let attachmentCount,
            let name,
            let arguments
        ) = packet else {
            Issue.record("Expected a binary event")
            return
        }

        #expect(namespace == "/admin")
        #expect(acknowledgementID == 19)
        #expect(attachmentCount == 2)
        #expect(name == "event")
        #expect(arguments == [.null])
    }

    @Test(
        "Missing and unknown packet types fail",
        arguments: [
            ("", SocketIOProtocolError.missingSocketIOPacketType),
            ("9payload", .unknownSocketIOPacketType("9")),
            (#"9/admin["payload"]"#, .unknownSocketIOPacketType("9"))
        ]
    )
    func packetType(text: String, expected: SocketIOProtocolError) {
        #expect(throws: expected) { try SocketIOCodec.decode(text) }
    }

    @Test(
        "Invalid binary headers fail",
        arguments: ["5", "5-", "50-[]", "5x-[]", "51[]"]
    )
    func binaryHeader(text: String) {
        #expect(throws: SocketIOProtocolError.invalidBinaryAttachmentCount) {
            try SocketIOCodec.decode(text)
        }
    }

    @Test("A namespace requires its terminating comma")
    func namespaceComma() {
        #expect(throws: SocketIOProtocolError.namespaceMissingComma) {
            try SocketIOCodec.decode(#"2/admin["event"]"#)
        }
    }

    @Test("An overflowing acknowledgement identifier fails")
    func acknowledgementOverflow() {
        #expect(throws: SocketIOProtocolError.invalidAcknowledgementID) {
            try SocketIOCodec.decode(#"299999999999999999999999999999["event"]"#)
        }
    }

    @Test("Acknowledgement packets require an identifier")
    func missingAcknowledgement() {
        #expect(throws: SocketIOProtocolError.missingAcknowledgementID) {
            try SocketIOCodec.decode("3[]")
        }
        #expect(throws: SocketIOProtocolError.missingAcknowledgementID) {
            try SocketIOCodec.decode("61-[]")
        }
    }

    @Test(
        "Invalid JSON fails",
        arguments: [#"2["event",}"#, "312invalid", "4invalid"]
    )
    func invalidJSON(text: String) {
        #expect(throws: SocketIOProtocolError.self) {
            try SocketIOCodec.decode(text)
        }
    }

    @Test("Event payload requires an array beginning with a string name")
    func invalidEvent() {
        #expect(throws: SocketIOProtocolError.invalidEventPayload) {
            try SocketIOCodec.decode(#"2{"event":1}"#)
        }
        #expect(throws: SocketIOProtocolError.missingEventName) {
            try SocketIOCodec.decode("2[]")
        }
        #expect(throws: SocketIOProtocolError.missingEventName) {
            try SocketIOCodec.decode("2[1]")
        }
    }

    @Test("Connect and connect-error payloads require objects")
    func connectPayloads() {
        #expect(throws: SocketIOProtocolError.invalidConnectPayload) {
            try SocketIOCodec.decode("0[]")
        }
        #expect(throws: SocketIOProtocolError.invalidConnectErrorPayload) {
            try SocketIOCodec.decode("4")
        }
        #expect(throws: SocketIOProtocolError.invalidConnectErrorPayload) {
            try SocketIOCodec.decode("4[]")
        }
    }
}
