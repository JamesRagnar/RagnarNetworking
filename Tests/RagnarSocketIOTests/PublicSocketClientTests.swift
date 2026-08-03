import Foundation
import RagnarSocketIO
import Testing

private enum PublicIncomingEvent: SocketEvent {
    typealias Schema = Int
    static let name = "incoming"
}

private enum PublicOutgoingEvent: EmittableSocketEvent {
    typealias Schema = Int
    static let name = "outgoing"
}

private struct AnyPublicEventStreamSource: Sendable {
    let yield: @Sendable ([SocketIOArgument]) -> Bool
}

private actor PublicTestSocketClient: SocketClient {
    private var sources: [String: AnyPublicEventStreamSource] = [:]

    func connect(to endpoint: SocketIOEndpoint) throws {}

    func disconnect() {}

    func invalidate() {
        sources.removeAll()
    }

    func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type,
        _ payload: Event.Schema
    ) async throws {}

    func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type
    ) async throws where Event.Schema == SocketEmptyBody {}

    func events<Event: SocketEvent>(
        for event: Event.Type,
        policy: SocketStreamPolicy?
    ) -> SocketEventStream<Event> {
        let source = SocketEventStream<Event>.makeStream(
            policy: policy ?? Event.defaultStreamPolicy
        )
        sources[Event.name] = AnyPublicEventStreamSource(
            yield: { source.yield(arguments: $0) }
        )
        return source.stream
    }

    func statusUpdates() -> AsyncStream<SocketConnectionStatus> {
        AsyncStream { continuation in
            continuation.yield(.disconnected)
            continuation.finish()
        }
    }

    func push<Value: Encodable & Sendable>(
        _ value: Value,
        eventName: String
    ) throws -> Bool {
        guard let source = sources[eventName] else { return false }
        return source.yield([try SocketIOArgument(value)])
    }
}

@Test("SocketClient exposes typed public contracts")
func publicSocketClientSurface() async {
    let client: any SocketClient = SocketIOClient(reconnectPolicy: .disabled)
    _ = await client.events(for: PublicIncomingEvent.self)
    await #expect(throws: SocketIOError.notConnected) {
        try await client.emit(PublicOutgoingEvent.self, 1)
    }
    await client.invalidate()
}

@Test("External SocketClient conformers can produce typed streams")
func externalSocketClientConformance() async throws {
    let client = PublicTestSocketClient()
    let policy = try SocketStreamPolicy.lossless(capacity: 1)
    let stream = await client.events(for: PublicIncomingEvent.self, policy: policy)

    #expect(try await client.push(1, eventName: PublicIncomingEvent.name))
    #expect(try await !client.push(2, eventName: PublicIncomingEvent.name))

    var iterator = stream.makeAsyncIterator()
    #expect(try await iterator.next() == 1)
    await #expect(throws: SocketIOError.bufferOverflow(eventName: PublicIncomingEvent.name)) {
        try await iterator.next()
    }
}
