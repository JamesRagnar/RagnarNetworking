import RagnarSocketIO
import Testing

@Suite(
    "Socket.IO Reference Reconnection",
    .enabled(if: socketIOIntegrationEnabled),
    .serialized
)
struct ReconnectionIntegrationTests {
    @Test("Transport close reconnects and preserves subscriptions")
    func transportReconnect() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            let ready = await client.events(for: FixtureReadyEvent.self)
            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)
            let first = try await nextValue(from: ready)
            let statuses = await client.statusUpdates()

            try await client.emit(FixtureCloseTransportEvent.self)
            try await waitForStatus(.reconnecting(attempt: 1), in: statuses)
            try await waitForStatus(.connected, from: client)
            let second = try await nextValue(from: ready)
            #expect(second.connectionNumber == first.connectionNumber + 1)
            await client.invalidate()
        }
    }

    @Test("Server namespace disconnect does not reconnect")
    func namespaceDisconnect() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)
            try await client.emit(FixtureDisconnectEvent.self)
            try await waitForStatus(.disconnected, from: client)
            try await Task.sleep(for: .milliseconds(250))
            try await waitForStatus(.disconnected, from: client)
            await client.invalidate()
        }
    }

    @Test("Acknowledgement-bearing events are discarded and the connection survives")
    func acknowledgement() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            let scalar = await client.events(for: FixtureScalarEvent.self)
            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)

            try await client.emit(FixtureAcknowledgementEvent.self)
            try await client.emit(FixtureCommandEvent.self)
            #expect(try await nextValue(from: scalar) == 42)
            await client.invalidate()
        }
    }
}
