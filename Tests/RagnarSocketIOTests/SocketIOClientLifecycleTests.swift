import Foundation
@testable import RagnarSocketIO
import RagnarWebSocket
import Testing

@Suite("Socket.IO Client Lifecycle", .serialized)
struct SocketIOClientLifecycleTests {
    @Test("Handshake publishes connecting and connected in protocol order")
    func handshake() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        var statuses = await client.statusUpdates().makeAsyncIterator()
        #expect(await statuses.next() == .disconnected)

        try await client.connect(to: socketTestEndpoint)
        #expect(await statuses.next() == .connecting)
        try await completeHandshake(client: client, webSocket: webSocket)
        #expect(await statuses.next() == .connected)
        #expect(await webSocket.sentMessages.first == .text("40"))

        await client.invalidate()
    }

    @Test("Typed events and emission use the packet codecs")
    func eventsAndEmission() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        let events = await client.events(for: NumberEvent.self)
        try await client.connect(to: socketTestEndpoint)
        try await completeHandshake(client: client, webSocket: webSocket)

        await webSocket.inject(.text(#"42["number",1]"#))
        var iterator = events.makeAsyncIterator()
        #expect(try await iterator.next() == 1)

        try await client.emit(OutgoingNumberEvent.self, 2)
        #expect(await webSocket.sentMessages.contains(.text(#"42["outgoing",2]"#)))
        await client.invalidate()
    }

    @Test("Emission rejects disconnected, connecting, oversized, and invalidated states")
    func emissionStates() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)

        await #expect(throws: SocketIOError.notConnected) {
            try await client.emit(OutgoingNumberEvent.self, 1)
        }
        try await client.connect(to: socketTestEndpoint)
        await #expect(throws: SocketIOError.notConnected) {
            try await client.emit(OutgoingNumberEvent.self, 1)
        }

        try await completeHandshake(
            client: client,
            webSocket: webSocket,
            openPayload: #"0{"sid":"session","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":2}"#
        )
        await #expect(throws: SocketIOError.self) {
            try await client.emit(OutgoingNumberEvent.self, 1)
        }

        await client.invalidate()
        await #expect(throws: SocketIOError.invalidated) {
            try await client.emit(OutgoingNumberEvent.self, 1)
        }
    }

    @Test("Same endpoint is a no-op and a valid replacement starts a new generation")
    func endpointReplacement() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        try await client.connect(to: socketTestEndpoint)
        try await completeHandshake(client: client, webSocket: webSocket)
        let initialCount = await webSocket.requests.count

        try await client.connect(to: socketTestEndpoint)
        #expect(await webSocket.requests.count == initialCount)

        let replacement = SocketIOEndpoint.server(URL(string: "https://replacement.example.com")!)
        try await client.connect(to: replacement)
        try await waitUntil { await webSocket.requests.count == initialCount + 1 }
        #expect(await webSocket.requests.last?.url?.host == "replacement.example.com")

        await client.invalidate()
    }

    @Test("Invalid replacement leaves a healthy connection unchanged")
    func invalidReplacement() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        try await client.connect(to: socketTestEndpoint)
        try await completeHandshake(client: client, webSocket: webSocket)
        let initialCount = await webSocket.requests.count

        let invalid = SocketIOEndpoint.server(URL(string: "ftp://example.com")!)
        await #expect(throws: SocketIOProtocolError.invalidEndpoint) {
            try await client.connect(to: invalid)
        }
        #expect(await client.status == .connected)
        #expect(await webSocket.requests.count == initialCount)

        await client.invalidate()
    }

    @Test("Disconnect preserves subscriptions and immediate reconnect is ordered after close")
    func disconnectReconnect() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        let events = await client.events(for: NumberEvent.self)
        try await client.connect(to: socketTestEndpoint)
        try await completeHandshake(client: client, webSocket: webSocket)

        await client.disconnect()
        try await client.connect(to: socketTestEndpoint)
        try await waitUntil { await webSocket.requests.count == 2 }
        await webSocket.inject(.text(
            #"0{"sid":"second","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#
        ))
        try await waitUntil { await webSocket.sentMessages.filter { $0 == .text("40") }.count == 2 }
        await webSocket.inject(.text("40"))
        try await waitUntil { await client.status == .connected }
        await webSocket.inject(.text(#"42["number",2]"#))

        var iterator = events.makeAsyncIterator()
        #expect(try await iterator.next() == 2)
        await client.invalidate()
    }

    @Test("Connect error and server disconnect are terminal without reconnect")
    func serverTerminalPackets() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let policy = try ReconnectPolicy(initialDelay: .zero, maximumDelay: .zero, jitter: 0)
        let client = makeSocketClient(webSocket: webSocket, clock: clock, reconnectPolicy: policy)
        try await client.connect(to: socketTestEndpoint)
        try await waitUntil { await webSocket.requests.count == 1 }
        await webSocket.inject(.text(
            #"0{"sid":"session","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#
        ))
        try await waitUntil { await webSocket.sentMessages.contains(.text("40")) }
        await webSocket.inject(.text(#"44{"message":"unauthorized"}"#))
        try await waitUntil {
            await client.status == .failed(.connectError(message: "unauthorized"))
        }
        #expect(await webSocket.requests.count == 1)

        try await client.connect(to: socketTestEndpoint)
        try await waitUntil { await webSocket.requests.count == 2 }
        await webSocket.inject(.text(
            #"0{"sid":"second","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#
        ))
        try await waitUntil { await webSocket.sentMessages.filter { $0 == .text("40") }.count == 2 }
        await webSocket.inject(.text("40"))
        try await waitUntil { await client.status == .connected }
        await webSocket.inject(.text("41"))
        try await waitUntil { await client.status == .disconnected }
        #expect(await webSocket.requests.count == 2)

        await client.invalidate()
    }

    @Test("Recognized unsupported packets fail explicitly without reconnect")
    func unsupportedPacket() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let policy = try ReconnectPolicy(
            initialDelay: .seconds(1),
            maximumDelay: .seconds(1),
            jitter: 0,
            maximumAttempts: 1
        )
        let client = makeSocketClient(webSocket: webSocket, clock: clock, reconnectPolicy: policy)
        try await client.connect(to: socketTestEndpoint)
        try await completeHandshake(client: client, webSocket: webSocket)

        await webSocket.inject(.text("431[]"))
        try await waitUntil {
            await client.status == .failed(.unsupportedCapability("Socket.IO acknowledgement"))
        }
        #expect(await webSocket.requests.count == 1)
        await client.invalidate()
    }

    @Test("Invalidation finishes status and event streams and rejects reconnect")
    func invalidation() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        var statuses = await client.statusUpdates().makeAsyncIterator()
        _ = await statuses.next()
        var events = await client.events(for: NumberEvent.self).makeAsyncIterator()

        await client.invalidate()
        #expect(await statuses.next() == .invalidated)
        #expect(await statuses.next() == nil)
        await #expect(throws: SocketIOError.invalidated) {
            try await events.next()
        }
        await #expect(throws: SocketIOError.invalidated) {
            try await client.connect(to: socketTestEndpoint)
        }
    }
}
