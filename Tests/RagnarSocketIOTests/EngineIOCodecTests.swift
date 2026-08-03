import Foundation
@testable import RagnarSocketIO
import Testing

@Suite("Engine.IO Codec")
struct EngineIOCodecTests {
    @Test("Open payload decodes protocol fields and heartbeat timing")
    func open() throws {
        let packet = try EngineIOCodec.decode(
            #"0{"sid":"session","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#
        )
        guard case .open(let payload) = packet else {
            Issue.record("Expected an open packet")
            return
        }

        #expect(payload.sessionID == "session")
        #expect(payload.upgrades.isEmpty)
        #expect(payload.pingInterval == .seconds(25))
        #expect(payload.pingTimeout == .seconds(20))
        #expect(payload.maxPayload == 1_000_000)

        let encoded = try EngineIOCodec.encode(packet)
        #expect(try EngineIOCodec.decode(encoded) == packet)
    }

    @Test(
        "Packet codes preserve their payloads",
        arguments: [
            ("1", EngineIOPacket.close),
            ("2probe", .ping("probe")),
            ("3probe", .pong("probe")),
            ("442[\"event\",1]", .message("42[\"event\",1]")),
            ("5", .upgrade),
            ("6", .noop)
        ]
    )
    func packetCodes(text: String, expected: EngineIOPacket) throws {
        let packet = try EngineIOCodec.decode(text)
        #expect(packet == expected)
        #expect(try EngineIOCodec.encode(packet) == text)
    }

    @Test("Ping payload is echoed by the corresponding pong")
    func pingPayload() throws {
        guard case .ping(let payload) = try EngineIOCodec.decode("2payload") else {
            Issue.record("Expected a ping packet")
            return
        }
        #expect(try EngineIOCodec.encode(.pong(payload)) == "3payload")
    }

    @Test(
        "Malformed open payloads fail",
        arguments: [
            "0",
            "0{}",
            #"0{"sid":"session"}"#,
            #"0{"sid":"session","upgrades":[],"pingInterval":"bad","pingTimeout":20,"maxPayload":1}"#
        ]
    )
    func malformedOpen(text: String) {
        #expect(throws: SocketIOProtocolError.malformedOpenPayload) {
            try EngineIOCodec.decode(text)
        }
    }

    @Test(
        "Invalid heartbeat timing fails",
        arguments: [0, -1, 86_400_001]
    )
    func invalidHeartbeat(milliseconds: Int) {
        let text = "0{\"sid\":\"session\",\"upgrades\":[],\"pingInterval\":\(milliseconds),"
            + "\"pingTimeout\":20,\"maxPayload\":1}"
        #expect(throws: SocketIOProtocolError.invalidHeartbeatTiming) {
            try EngineIOCodec.decode(text)
        }
    }

    @Test("Invalid maximum payload fails")
    func invalidMaximumPayload() {
        let text = #"0{"sid":"session","upgrades":[],"pingInterval":20,"pingTimeout":20,"maxPayload":0}"#
        #expect(throws: SocketIOProtocolError.invalidMaximumPayload) {
            try EngineIOCodec.decode(text)
        }
    }

    @Test("Unknown and missing packet types fail without retaining payload text")
    func unknownPacket() {
        #expect(throws: SocketIOProtocolError.unknownEngineIOPacketType(nil)) {
            try EngineIOCodec.decode("")
        }
        #expect(throws: SocketIOProtocolError.unknownEngineIOPacketType("9")) {
            try EngineIOCodec.decode("9sensitive payload")
        }
    }

    @Test("Message size validation uses UTF-8 byte count")
    func maximumPayload() throws {
        try EngineIOPacket.message("é").validateMessageSize(maximum: 2)
        #expect(throws: SocketIOProtocolError.messageExceedsMaximumPayload(limit: 1, actual: 2)) {
            try EngineIOPacket.message("é").validateMessageSize(maximum: 1)
        }
    }

    @Test("Upgrade and noop remain distinguishable valid grammar")
    func unsupportedFeatures() throws {
        #expect(try EngineIOCodec.decode("5") == .upgrade)
        #expect(try EngineIOCodec.decode("6") == .noop)
        #expect(!SocketIOProtocolError.unsupportedTransportFeature("upgrade").localizedDescription.isEmpty)
    }
}
