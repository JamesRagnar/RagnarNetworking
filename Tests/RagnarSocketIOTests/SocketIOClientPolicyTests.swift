import Foundation
@testable import RagnarSocketIO
import RagnarWebSocket
import Testing

@Suite("Socket.IO Client Policy", .serialized)
struct SocketIOClientPolicyTests {
    @Test("Reconnect uses initial delay and resets after success")
    func reconnectReset() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let policy = try ReconnectPolicy(
            initialDelay: .seconds(1),
            maximumDelay: .seconds(8),
            multiplier: 2,
            jitter: 0,
            maximumAttempts: 3
        )
        let client = makeSocketClient(webSocket: webSocket, clock: clock, reconnectPolicy: policy)
        try await client.connect(to: socketTestEndpoint)
        try await waitUntil { await webSocket.requests.count == 1 }
        await webSocket.failReceive()
        try await waitUntil { await clock.pendingDurations().contains(.seconds(1)) }
        await clock.advance(.seconds(1))
        try await waitUntil { await webSocket.requests.count == 2 }
        try await completeHandshake(client: client, webSocket: webSocket)

        await webSocket.failReceive()
        try await waitUntil { await clock.pendingDurations().contains(.seconds(1)) }
        await client.invalidate()
    }

    @Test("Heartbeat resets on ping, sends pong, and reconnects on timeout")
    func heartbeat() async throws {
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
        try await completeHandshake(
            client: client,
            webSocket: webSocket,
            openPayload: #"0{"sid":"session","upgrades":[],"pingInterval":10,"pingTimeout":5,"maxPayload":1000000}"#
        )

        await webSocket.inject(.text("2probe"))
        try await waitUntil { await webSocket.sentMessages.contains(.text("3probe")) }
        try await waitUntil { await clock.pendingDurations().contains(.milliseconds(15)) }
        await clock.advance(.milliseconds(15))
        try await waitUntil { await client.status == .reconnecting(attempt: 1) }

        await client.invalidate()
    }

    @Test("Namespace timeout is terminal even when reconnect is enabled")
    func namespaceTimeout() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let policy = try ReconnectPolicy(
            initialDelay: .seconds(1),
            maximumDelay: .seconds(1),
            jitter: 0,
            maximumAttempts: 1
        )
        let client = makeSocketClient(
            webSocket: webSocket,
            clock: clock,
            reconnectPolicy: policy,
            namespaceTimeout: .seconds(2)
        )
        try await client.connect(to: socketTestEndpoint)
        try await waitUntil { await webSocket.requests.count == 1 }
        await webSocket.inject(.text(
            #"0{"sid":"session","upgrades":[],"pingInterval":100000,"pingTimeout":100000,"maxPayload":1000000}"#
        ))
        try await waitUntil { await clock.pendingDurations().contains(.seconds(2)) }
        await clock.advance(.seconds(2))
        try await waitUntil { await client.status == .failed(.namespaceTimeout) }
        #expect(await webSocket.requests.count == 1)

        await client.invalidate()
    }

    @Test("Send failure tears down the generation and applies reconnect policy")
    func sendFailure() async throws {
        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let client = makeSocketClient(webSocket: webSocket, clock: clock)
        try await client.connect(to: socketTestEndpoint)
        try await completeHandshake(client: client, webSocket: webSocket)
        await webSocket.failNextSend()

        await #expect(throws: TestTransportFailure.sendFailed) {
            try await client.emit(OutgoingNumberEvent.self, 1)
        }
        try await waitUntil {
            guard case .failed(.transport) = await client.status else { return false }
            return true
        }
        await client.invalidate()
    }

    @Test("Reconnect policy validates configuration and delay bounds")
    func policyValidation() async throws {
        #expect(throws: ReconnectPolicyError.invalidDelay) {
            try ReconnectPolicy(initialDelay: .seconds(2), maximumDelay: .seconds(1))
        }
        #expect(throws: ReconnectPolicyError.invalidMultiplier) {
            try ReconnectPolicy(multiplier: 0.5)
        }
        #expect(throws: ReconnectPolicyError.invalidJitter) {
            try ReconnectPolicy(jitter: 2)
        }
        #expect(throws: ReconnectPolicyError.invalidMaximumAttempts) {
            try ReconnectPolicy(maximumAttempts: -1)
        }

        let webSocket = TestWebSocketClient()
        let clock = ManualSocketIOClock()
        let policy = try ReconnectPolicy(
            initialDelay: .seconds(2),
            maximumDelay: .seconds(5),
            multiplier: 3,
            jitter: 0.5
        )
        let low = makeSocketClient(
            webSocket: webSocket,
            clock: clock,
            reconnectPolicy: policy,
            randomValue: 0
        )
        let high = makeSocketClient(
            webSocket: webSocket,
            clock: clock,
            reconnectPolicy: policy,
            randomValue: 1
        )
        #expect(await low.reconnectDelay(attempt: 1) == .seconds(1))
        #expect(await high.reconnectDelay(attempt: 1) == .seconds(3))
        #expect(await high.reconnectDelay(attempt: 3) == .seconds(5))
        #expect(await high.canReconnect(attempt: 100))

        let cappedPolicy = try ReconnectPolicy(maximumAttempts: 2)
        let capped = makeSocketClient(
            webSocket: webSocket,
            clock: clock,
            reconnectPolicy: cappedPolicy
        )
        #expect(await capped.canReconnect(attempt: 2))
        #expect(!(await capped.canReconnect(attempt: 3)))
    }
}
