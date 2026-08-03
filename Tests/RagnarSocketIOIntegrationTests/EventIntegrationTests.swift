import RagnarSocketIO
import Testing

@Suite(
    "Socket.IO Reference Events",
    .enabled(if: socketIOIntegrationEnabled),
    .serialized
)
struct EventIntegrationTests {
    @Test("Typed contracts preserve supported event shapes")
    func eventShapes() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            let zero = await client.events(for: FixtureZeroEvent.self)
            let null = await client.events(for: FixtureNullEvent.self)
            let scalar = await client.events(for: FixtureScalarEvent.self)
            let object = await client.events(for: FixtureObjectEvent.self)
            let array = await client.events(for: FixtureArrayEvent.self)
            let multi = await client.events(for: FixtureMultiEvent.self)

            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)
            try await client.emit(FixtureCommandEvent.self)

            _ = try await nextValue(from: zero)
            _ = try await nextValue(from: null)
            #expect(try await nextValue(from: scalar) == 42)
            #expect(try await nextValue(from: object) == .init(value: 1))
            #expect(try await nextValue(from: array) == [1, 2])
            #expect(try await nextValue(from: multi) == .init(number: 1, text: "two"))
            await client.invalidate()
        }
    }

    @Test("Client emission round trips through the reference server")
    func emission() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            let scalar = await client.events(for: FixtureEchoEvent<Int>.self)
            let object = await client.events(for: FixtureObjectEchoEvent.self)
            let array = await client.events(for: FixtureArrayEchoEvent.self)
            let multi = await client.events(for: FixtureMultiEvent.self)
            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)

            try await client.emit(FixtureEchoEvent<Int>.self, 7)
            #expect(try await nextValue(from: scalar) == 7)

            let objectValue = FixtureObjectEvent.Schema(value: 3)
            try await client.emit(FixtureObjectEchoEvent.self, objectValue)
            #expect(try await nextValue(from: object) == objectValue)

            try await client.emit(FixtureArrayEchoEvent.self, [4, 5])
            #expect(try await nextValue(from: array) == [4, 5])

            let value = FixtureMultiEvent.Schema(number: 2, text: "value")
            try await client.emit(FixtureMultiEvent.self, value)
            #expect(try await nextValue(from: multi) == value)
            await client.invalidate()
        }
    }

    @Test("Schema failure terminates only the mismatched subscription")
    func schemaFailure() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            let correct = await client.events(for: FixtureScalarEvent.self)
            let mismatched = await client.events(for: FixtureEchoEvent<String>.self)
            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)

            try await client.emit(FixtureEchoEvent<Int>.self, 1)
            await #expect(throws: SocketIOError.self) {
                try await nextValue(from: mismatched)
            }

            try await client.emit(FixtureCommandEvent.self)
            #expect(try await nextValue(from: correct) == 42)
            await client.invalidate()
        }
    }
}
