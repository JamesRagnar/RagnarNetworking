import Foundation
import Testing
@testable import RagnarNetworking

private enum SocketServiceTestError: Error {
    case timeout
    case noValue
}

private func firstValue<T: Sendable>(
    from stream: AsyncStream<T>,
    timeout: UInt64 = 1_000_000_000
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let value = await iterator.next() else {
                throw SocketServiceTestError.noValue
            }
            return value
        }

        group.addTask {
            try await Task.sleep(nanoseconds: timeout)
            throw SocketServiceTestError.timeout
        }

        let value = try await group.next()
        group.cancelAll()
        guard let value else {
            throw SocketServiceTestError.noValue
        }
        return value
    }
}

private func waitForCondition(
    timeout: UInt64 = 1_000_000_000,
    poll: UInt64 = 50_000_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeout
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: poll)
    }
    return await condition()
}

struct ChatEvent: SocketEvent {
    static let name = "chat"

    struct Schema: Codable, Sendable {
        let message: String
    }
}

struct OutgoingEvent: SocketEvent {
    static let name = "send"

    struct Schema: Codable, Sendable, SocketPayload {
        let text: String
    }
}

actor TestSocketClient: SocketClientProtocol {
    var sid: String? = nil

    private var emitted: [(String, SocketPayloadValue)] = []
    private var didSetEventHandler = false
    private var didSetStatusHandler = false
    private var eventHandler: (@Sendable (SocketEventSnapshot) -> Void)?
    private var statusHandler: (@Sendable (SocketService.SocketStatus) -> Void)?

    func setEventHandler(_ handler: @Sendable @escaping (SocketEventSnapshot) -> Void) {
        didSetEventHandler = true
        eventHandler = handler
    }

    func setStatusHandler(_ handler: @Sendable @escaping (SocketService.SocketStatus) -> Void) {
        didSetStatusHandler = true
        statusHandler = handler
    }

    func emit(_ event: String, _ payload: SocketPayloadValue) throws {
        emitted.append((event, payload))
    }

    func connect() {}

    func disconnect() {}

    func hasEventHandler() -> Bool {
        didSetEventHandler
    }

    func hasStatusHandler() -> Bool {
        didSetStatusHandler
    }

    func emittedCount() -> Int {
        emitted.count
    }

    func firstEmittedEventName() -> String? {
        emitted.first?.0
    }

    func simulateEvent(name: String, items: [Any]) {
        let snapshot = SocketEventSnapshot(event: name, items: items)
        eventHandler?(snapshot)
    }

    func simulateStatus(_ status: SocketService.SocketStatus) {
        statusHandler?(status)
    }
}

@Suite("SocketService Tests")
struct SocketServiceTests {

    @Test
    func observeStatusImmediateValue() async throws {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        let stream = await service.observeStatus()
        let value = try await firstValue(from: stream)
        #expect(value == .notConnected)
    }

    @Test
    func observeStatusReceivesUpdates() async throws {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        let stream = await service.observeStatus()
        var iterator = stream.makeAsyncIterator()

        let didConfigure = await waitForCondition {
            let hasEvent = await client.hasEventHandler()
            let hasStatus = await client.hasStatusHandler()
            return hasEvent && hasStatus
        }
        #expect(didConfigure)

        let initial = await iterator.next()
        #expect(initial == .notConnected)

        await client.simulateStatus(.connected)

        let updated = await iterator.next()
        #expect(updated == .connected)
    }

    @Test
    func statusUpdatesWithoutObservers() async {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        await service.connect()

        let didConfigure = await waitForCondition {
            let hasEvent = await client.hasEventHandler()
            let hasStatus = await client.hasStatusHandler()
            return hasEvent && hasStatus
        }
        #expect(didConfigure)

        await client.simulateStatus(.connected)
        let didUpdate = await waitForCondition {
            let status = await service.status()
            return status == .connected
        }
        #expect(didUpdate)
    }

    @Test
    func observeAllEventsReceivesAnyEvent() async throws {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        let stream = await service.observeAllEvents()
        let value = Task { try await firstValue(from: stream) }

        let didConfigure = await waitForCondition {
            await client.hasEventHandler()
        }
        #expect(didConfigure)

        await client.simulateEvent(
            name: ChatEvent.name,
            items: [["message": "hello"]]
        )

        let event = try await value.value
        #expect(event.event == ChatEvent.name)
    }

    @Test
    func observeTypedEventDecodes() async throws {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        let stream = await service.observeEvent(ChatEvent.self)
        let value = Task { try await firstValue(from: stream) }

        let didConfigure = await waitForCondition {
            await client.hasEventHandler()
        }
        #expect(didConfigure)

        await client.simulateEvent(
            name: ChatEvent.name,
            items: [["message": "hi"]]
        )

        let decoded = try await value.value
        #expect(decoded.message == "hi")
    }

    @Test
    func multipleObserversReceiveSameEvent() async throws {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        let streamA = await service.observeEvent(ChatEvent.self)
        let streamB = await service.observeEvent(ChatEvent.self)

        let valueA = Task { try await firstValue(from: streamA) }
        let valueB = Task { try await firstValue(from: streamB) }

        let didConfigure = await waitForCondition {
            await client.hasEventHandler()
        }
        #expect(didConfigure)

        await client.simulateEvent(
            name: ChatEvent.name,
            items: [["message": "yo"]]
        )

        let decodedA = try await valueA.value
        let decodedB = try await valueB.value

        #expect(decodedA.message == "yo")
        #expect(decodedB.message == "yo")
    }

    @Test
    func sendEventEmitsThroughClient() async {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        await service.sendEvent(OutgoingEvent.self, .init(text: "ping"))
        let count = await client.emittedCount()
        let name = await client.firstEmittedEventName()
        #expect(count == 1)
        #expect(name == OutgoingEvent.name)
    }

    @Test
    func cancelledObserverDoesNotBlockOthers() async throws {
        let client = TestSocketClient()
        let service = SocketService(client: client)

        let streamA = await service.observeAllEvents()
        let streamB = await service.observeAllEvents()

        let valueA = Task { try await firstValue(from: streamA, timeout: 500_000_000) }
        let valueB = Task { try await firstValue(from: streamB) }

        let didConfigure = await waitForCondition {
            await client.hasEventHandler()
        }
        #expect(didConfigure)

        valueA.cancel()
        _ = await valueA.result

        await client.simulateEvent(
            name: ChatEvent.name,
            items: [["message": "bye"]]
        )

        let event = try await valueB.value
        #expect(event.event == ChatEvent.name)
    }
}
