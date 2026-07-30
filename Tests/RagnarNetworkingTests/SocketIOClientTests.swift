import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Mock WebSocket Task

final class MockWebSocketTask: WebSocketTask, @unchecked Sendable {

    // AsyncStream used to feed messages into receive()
    private let (stream, continuation) = AsyncStream<URLSessionWebSocketTask.Message>.makeStream()
    private var iterator: AsyncStream<URLSessionWebSocketTask.Message>.AsyncIterator

    nonisolated(unsafe) var sentMessages: [URLSessionWebSocketTask.Message] = []
    nonisolated(unsafe) var resumeCount: Int = 0
    nonisolated(unsafe) var cancelCount: Int = 0

    init() {
        iterator = stream.makeAsyncIterator()
    }

    func inject(text: String) {
        continuation.yield(.string(text))
    }

    func simulateDisconnect() {
        continuation.finish()
    }

    func resume() {
        resumeCount += 1
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelCount += 1
        continuation.finish()
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard let message = await iterator.next() else {
            throw URLError(.networkConnectionLost)
        }
        return message
    }
}

// MARK: - Test Event

private struct PingEvent: SocketEvent {
    static let name = "test_ping"
    struct Schema: Codable, Sendable, Equatable {
        let message: String
    }
}

private struct EmitEvent: SocketEvent {
    static let name = "test_emit"
    struct Schema: Codable, Sendable, Equatable {
        let data: String
    }
}

private struct EmptyEvent: SocketEvent {
    static let name = "test_empty"
    typealias Schema = SocketEmptyBody
}

// MARK: - Helpers

private let testURL = URL(string: "ws://example.com/socket.io/")!
private let testBaseURL = URL(string: "http://example.com")!

/// Performs the standard Socket.IO handshake on the given mock task.
/// inject "0{}" → client responds with "40"
/// inject "40"  → client sets status to .connected
private func performHandshake(on task: MockWebSocketTask) async {
    task.inject(text: "0{}")
    // Wait for the client to send "40" before injecting the connect ack
    var attempts = 0
    while task.sentMessages.isEmpty && attempts < 100 {
        await Task.yield()
        attempts += 1
    }
    task.inject(text: "40")
}

/// Returns the next value from a status stream, or nil if the stream ends.
private func awaitNextStatus(
    from stream: AsyncStream<SocketIOClient.Status>
) async -> SocketIOClient.Status? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

/// Returns the next value from a typed event stream.
private func awaitNextEvent<T: Sendable>(
    from stream: AsyncStream<T>
) async -> T? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

/// Makes a SocketIOClient that cycles through the given tasks in order.
private func makeSocket(tasks: [MockWebSocketTask]) -> SocketIOClient {
    nonisolated(unsafe) var index = 0
    return SocketIOClient(
        url: testURL,
        reconnect: .disabled,
        taskFactory: { _, _ in
            let task = tasks[index]
            index += 1
            return task
        }
    )
}

// MARK: - Manual Sleep Clock

/// A `SleepClock` a test controls directly: `sleep(for:)` suspends until the test calls
/// `advanceLatest()`, and every requested duration is recorded for inspection. Resolving
/// by "latest still-pending" (rather than call order) is robust to `resetHeartbeat`
/// cancelling an older pending sleep slightly after a newer one is already registered.
private actor ManualSleepClock: SleepClock {
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    /// Resolves the most recently registered still-pending sleep, as if its duration elapsed.
    func advanceLatest() {
        guard let latestID = pending.keys.max(), let continuation = pending.removeValue(forKey: latestID) else {
            return
        }
        continuation.resume()
    }

    private func cancel(_ id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }
}

/// Waits until `clock.requestedDurations` stops growing for several consecutive
/// scheduler turns. `resetHeartbeat` registers its sleep asynchronously (inside a
/// spawned `Task`), so this gives any in-flight reset a chance to register - and,
/// crucially, gives any reset it *supersedes* a chance to be cancelled and removed -
/// before the test calls `advanceLatest()`, so "most recently registered" reliably
/// means "currently active" rather than racing a stale, not-yet-cleaned-up entry.
private func waitForClockQuiescence(_ clock: ManualSleepClock) async {
    var previousCount = -1
    var stableStreak = 0
    var attempts = 0
    while stableStreak < 10 && attempts < 500 {
        let count = await clock.requestedDurations.count
        if count == previousCount {
            stableStreak += 1
        } else {
            stableStreak = 0
            previousCount = count
        }
        await Task.yield()
        attempts += 1
    }
}

// MARK: - Suite

@Suite("SocketIOClient Tests", .timeLimit(.minutes(1)))
struct SocketIOClientTests {

    // MARK: - URL Construction

    @Test("webSocketURL converts http:// to ws:// with correct path and query")
    func urlConstructionHttpToWs() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "http://example.com")!)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.scheme == "ws")
        #expect(components?.path == "/socket.io/")
        let queryNames = components?.queryItems?.map(\.name) ?? []
        #expect(queryNames.contains("EIO"))
        #expect(queryNames.contains("transport"))
        #expect(components?.queryItems?.first(where: { $0.name == "transport" })?.value == "websocket")
    }

    @Test("webSocketURL converts https:// to wss://")
    func urlConstructionHttpsToWss() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "https://secure.example.com")!)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.scheme == "wss")
    }

    @Test("webSocketURL with no base path produces /socket.io/")
    func urlConstructionWithNoBasePath() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "http://example.com")!)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.path == "/socket.io/")
    }

    @Test("webSocketURL joins a server URL path prefix rather than discarding it")
    func urlConstructionJoinsExistingPathPrefix() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "http://example.com/api/v2")!)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.path == "/api/v2/socket.io/")
    }

    @Test("webSocketURL does not produce a doubled separator when the base path has a trailing slash")
    func urlConstructionAvoidsDoubledSeparator() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "http://example.com/api/v2/")!)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.path == "/api/v2/socket.io/")
    }

    @Test("webSocketURL preserves existing query items alongside EIO and transport")
    func urlConstructionPreservesExistingQueryItems() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "http://example.com?tenant=acme")!)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let queryNames = components?.queryItems?.map(\.name) ?? []
        #expect(queryNames.contains("tenant"))
        #expect(queryNames.contains("EIO"))
        #expect(queryNames.contains("transport"))
        #expect(components?.queryItems?.first(where: { $0.name == "tenant" })?.value == "acme")
    }

    @Test("webSocketURL honours a custom path argument")
    func urlConstructionHonoursCustomPath() {
        let url = SocketIOClient.webSocketURL(for: URL(string: "http://example.com")!, path: "custom-path")
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components?.path == "/custom-path/")
    }

    // MARK: - Connection Lifecycle

    @Test("connect() calls resume() on the WebSocket task")
    func connectCallsResume() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        await socket.connect()

        // Give the connection loop a moment to start
        await Task.yield()

        #expect(task.resumeCount == 1)
    }

    @Test("After handshake, statusUpdates() stream reaches .connected")
    func handshakeLeadsToConnectedStatus() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        // Consume initial .disconnected
        var iterator = statusStream.makeAsyncIterator()
        _ = await iterator.next() // .disconnected

        await performHandshake(on: task)

        let connecting = await iterator.next()
        #expect(connecting == .connecting)

        let connected = await iterator.next()
        #expect(connected == .connected)
    }

    @Test("disconnect() transitions status back to .disconnected")
    func disconnectTransitionsToDisconnected() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var iterator = statusStream.makeAsyncIterator()
        _ = await iterator.next() // .disconnected (initial)

        await performHandshake(on: task)

        _ = await iterator.next() // .connecting
        _ = await iterator.next() // .connected

        await socket.disconnect()

        let disconnected = await iterator.next()
        #expect(disconnected == .disconnected)
    }

    @Test("connect() after disconnect() creates a new connection")
    func connectAfterDisconnectCreatesNewConnection() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        let socket = makeSocket(tasks: [task1, task2])

        await socket.connect()
        await Task.yield()
        await socket.disconnect()

        // Wait for disconnect to settle
        await Task.yield()

        await socket.connect()
        await Task.yield()

        #expect(task1.resumeCount == 1)
        #expect(task2.resumeCount == 1)
    }

    @Test("invalidate() finishes the statusUpdates() stream")
    func invalidateFinishesStatusStream() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var iterator = statusStream.makeAsyncIterator()
        _ = await iterator.next() // consume initial

        await socket.invalidate()

        // After invalidate, stream should finish (next returns nil)
        // Drain any buffered values until nil
        var finished = false
        for _ in 0..<10 {
            let next = await iterator.next()
            if next == nil {
                finished = true
                break
            }
        }
        #expect(finished)
    }

    // MARK: - Status Stream

    @Test("statusUpdates() emits the current status immediately on subscription")
    func statusUpdatesEmitsCurrentStatusImmediately() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()

        var iterator = statusStream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .disconnected)
    }

    @Test("Multiple statusUpdates() streams each receive all transitions")
    func multipleStatusStreamsEachReceiveTransitions() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let stream1 = await socket.statusUpdates()
        let stream2 = await socket.statusUpdates()

        await socket.connect()

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        _ = await iter1.next() // .disconnected
        _ = await iter2.next() // .disconnected

        await performHandshake(on: task)

        let connecting1 = await iter1.next()
        let connecting2 = await iter2.next()
        #expect(connecting1 == .connecting)
        #expect(connecting2 == .connecting)

        let connected1 = await iter1.next()
        let connected2 = await iter2.next()
        #expect(connected1 == .connected)
        #expect(connected2 == .connected)
    }

    // MARK: - Events

    @Test("events(for:) delivers a typed decoded event after handshake")
    func eventsDeliverTypedEvent() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let eventStream = await socket.events(for: PingEvent.self)
        let statusStream = await socket.statusUpdates()

        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected

        await performHandshake(on: task)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        let payload = try! JSONEncoder().encode(PingEvent.Schema(message: "hello"))
        let json = String(data: payload, encoding: .utf8)!
        task.inject(text: #"42["\#(PingEvent.name)",\#(json)]"#)

        var eventIterator = eventStream.makeAsyncIterator()
        let event = await eventIterator.next()
        #expect(event?.message == "hello")
    }

    @Test("Multiple independent events(for:) streams for the same event type each receive the event")
    func multipleEventStreamsEachReceiveEvent() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let stream1 = await socket.events(for: PingEvent.self)
        let stream2 = await socket.events(for: PingEvent.self)
        let statusStream = await socket.statusUpdates()

        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        await performHandshake(on: task)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        let payload = try! JSONEncoder().encode(PingEvent.Schema(message: "broadcast"))
        let json = String(data: payload, encoding: .utf8)!
        task.inject(text: #"42["\#(PingEvent.name)",\#(json)]"#)

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let event1 = await iter1.next()
        let event2 = await iter2.next()
        #expect(event1?.message == "broadcast")
        #expect(event2?.message == "broadcast")
    }

    @Test("events(for:) stream continues after reconnect")
    func eventStreamSurvivesReconnect() async throws {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        let socket = makeSocket(tasks: [task1, task2])

        let eventStream = await socket.events(for: PingEvent.self)
        let statusStream = await socket.statusUpdates()

        // Reconnect is disabled; reconnection is performed manually by calling connect() again.
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected

        await performHandshake(on: task1)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        // Disconnect by simulating network loss
        task1.simulateDisconnect()
        _ = await statusIterator.next() // .disconnected

        // Reconnect
        await socket.connect()
        await performHandshake(on: task2)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        // Inject an event on the new task
        let payload = try! JSONEncoder().encode(PingEvent.Schema(message: "after-reconnect"))
        let json = String(data: payload, encoding: .utf8)!
        task2.inject(text: #"42["\#(PingEvent.name)",\#(json)]"#)

        var eventIterator = eventStream.makeAsyncIterator()
        let event = await eventIterator.next()
        #expect(event?.message == "after-reconnect")
    }

    // MARK: - Emit

    @Test("emit(_:_:) with payload sends the correct Socket.IO frame")
    func emitWithPayloadSendsCorrectFrame() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])
        let statusStream = await socket.statusUpdates()

        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        await performHandshake(on: task)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        // Clear the "40" connect message sent during handshake
        let priorCount = task.sentMessages.count

        try await socket.emit(EmitEvent.self, EmitEvent.Schema(data: "test-value"))

        let messages = task.sentMessages
        #expect(messages.count == priorCount + 1)

        if case .string(let text) = messages.last {
            #expect(text.hasPrefix(#"42["\#(EmitEvent.name)","#))
            #expect(text.contains("test-value"))
        } else {
            Issue.record("Expected a string message")
        }
    }

    @Test("emit(_:) without payload sends the correct Socket.IO frame")
    func emitWithoutPayloadSendsCorrectFrame() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])
        let statusStream = await socket.statusUpdates()

        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        await performHandshake(on: task)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        let priorCount = task.sentMessages.count

        try await socket.emit(EmptyEvent.self)

        let messages = task.sentMessages
        #expect(messages.count == priorCount + 1)

        if case .string(let text) = messages.last {
            #expect(text == #"42["\#(EmptyEvent.name)"]"#)
        } else {
            Issue.record("Expected a string message")
        }
    }

    @Test("emit throws SocketIOError.notConnected when not connected")
    func emitThrowsWhenNotConnected() async {
        let socket = SocketIOClient(url: testURL, reconnect: .disabled)

        await #expect(throws: SocketIOError.notConnected) {
            try await socket.emit(EmptyEvent.self)
        }
    }

    // MARK: - Protocol Handling

    @Test("PING (\"2\") receives a PONG (\"3\") response")
    func pingReceivesPong() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])
        let statusStream = await socket.statusUpdates()

        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        await performHandshake(on: task)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        let priorCount = task.sentMessages.count

        // Inject PING
        task.inject(text: "2")

        // Wait for PONG to arrive in sentMessages
        var attempts = 0
        while task.sentMessages.count == priorCount && attempts < 100 {
            await Task.yield()
            attempts += 1
        }

        let messages = task.sentMessages
        #expect(messages.count == priorCount + 1)

        if case .string(let text) = messages.last {
            #expect(text == "3")
        } else {
            Issue.record("Expected a string PONG message")
        }
    }

    // MARK: - Reconnect

    @Test("reconnect(to:) switches to the new URL and re-establishes connection")
    func reconnectToNewURL() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        nonisolated(unsafe) var usedURLs: [URL] = []
        nonisolated(unsafe) var taskIndex = 0
        let tasks = [task1, task2]
        let socket = SocketIOClient(
            url: URL(string: "ws://old.example.com/")!,
            reconnect: .disabled,
            taskFactory: { url, _ in
                usedURLs.append(url)
                let t = tasks[taskIndex]
                taskIndex += 1
                return t
            }
        )

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected

        await performHandshake(on: task1)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        let newURL = URL(string: "ws://new.example.com/")!
        await socket.reconnect(to: newURL)

        _ = await statusIterator.next() // .disconnected

        await performHandshake(on: task2)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        #expect(usedURLs.last == newURL)

        await socket.invalidate()
    }

    @Test("reconnect(to:) works after an explicit disconnect")
    func reconnectAfterDisconnectStartsANewConnection() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        let socket = makeSocket(tasks: [task1, task2])

        await socket.connect()
        await Task.yield()
        await socket.disconnect()

        let newURL = URL(string: "ws://new.example.com/")!
        await socket.reconnect(to: newURL)
        await Task.yield()

        #expect(task1.resumeCount == 1)
        #expect(task2.resumeCount == 1)
    }

    // MARK: - Malformed Payloads

    @Test("events(for:) silently drops payloads that do not match the schema")
    func eventStreamDropsMalformedPayload() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let eventStream = await socket.events(for: PingEvent.self)
        let statusStream = await socket.statusUpdates()

        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        await performHandshake(on: task)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        // Inject a payload that does not match PingEvent.Schema (not a JSON object)
        task.inject(text: #"42["\#(PingEvent.name)","not-an-object"]"#)

        // Inject a valid payload immediately after — this one should be received
        let validPayload = try JSONEncoder().encode(PingEvent.Schema(message: "valid"))
        let json = String(data: validPayload, encoding: .utf8)!
        task.inject(text: #"42["\#(PingEvent.name)",\#(json)]"#)

        var eventIterator = eventStream.makeAsyncIterator()
        let event = await eventIterator.next()
        #expect(event?.message == "valid")
    }

    // MARK: - Invalidate with Active Event Streams

    @Test("invalidate() finishes all registered event streams")
    func invalidateFinishesEventStreams() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let eventStream = await socket.events(for: PingEvent.self)
        await socket.connect()
        await Task.yield()

        await socket.invalidate()

        var eventIterator = eventStream.makeAsyncIterator()
        var finished = false
        for _ in 0..<10 {
            guard await eventIterator.next() != nil else {
                finished = true
                break
            }
        }
        #expect(finished)
    }

    // MARK: - Automatic Reconnect

    @Test("Automatic reconnect retries after network loss using reconnect policy")
    func automaticReconnectAfterNetworkLoss() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        nonisolated(unsafe) var taskIndex = 0
        let tasks = [task1, task2]
        let socket = SocketIOClient(
            url: testURL,
            reconnect: .init(enabled: true, initialDelay: .milliseconds(1), maxDelay: .seconds(1), multiplier: 2.0),
            taskFactory: { _, _ in
                let t = tasks[taskIndex]
                taskIndex += 1
                return t
            }
        )

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected

        await performHandshake(on: task1)
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        // Simulate network loss — triggers auto-reconnect
        task1.simulateDisconnect()

        _ = await statusIterator.next() // .disconnected (after receive throws)
        _ = await statusIterator.next() // .connecting (after initialDelay sleep)

        await performHandshake(on: task2)
        _ = await statusIterator.next() // .connected

        #expect(task1.resumeCount == 1)
        #expect(task2.resumeCount == 1)

        await socket.invalidate()
    }

    // MARK: - Heartbeat Timeout

    @Test("open payload with custom pingInterval/pingTimeout is used for the heartbeat deadline")
    func heartbeatUsesParsedPingIntervalAndTimeout() async {
        let task = MockWebSocketTask()
        let clock = ManualSleepClock()
        let socket = SocketIOClient(
            url: testURL,
            reconnect: .disabled,
            taskFactory: { _, _ in task },
            clock: clock
        )

        await socket.connect()
        task.inject(text: #"0{"pingInterval":5000,"pingTimeout":3000}"#)

        // resetHeartbeat schedules a Task that calls clock.sleep(for:) - the duration is
        // recorded asynchronously, not synchronously as part of handling the frame - so
        // poll for it rather than checking immediately after the "40" send is observed.
        var durations: [Duration] = []
        var attempts = 0
        while durations.last != .seconds(8) && attempts < 100 {
            await Task.yield()
            attempts += 1
            durations = await clock.requestedDurations
        }

        #expect(durations.last == .seconds(8))
    }

    @Test("Missing or unparseable open payload falls back to default heartbeat timing")
    func openPayloadFallsBackToDefaultsWhenUnparseable() async {
        let task = MockWebSocketTask()
        let clock = ManualSleepClock()
        let socket = SocketIOClient(
            url: testURL,
            reconnect: .disabled,
            taskFactory: { _, _ in task },
            clock: clock
        )

        await socket.connect()
        task.inject(text: "0not-json")

        var durations: [Duration] = []
        var attempts = 0
        while durations.last != .seconds(45) && attempts < 100 {
            await Task.yield()
            attempts += 1
            durations = await clock.requestedDurations
        }

        #expect(durations.last == .seconds(45))
    }

    @Test("Inbound frames within the heartbeat window keep the connection alive")
    func framesWithinHeartbeatWindowPreventTimeout() async {
        let task = MockWebSocketTask()
        let clock = ManualSleepClock()
        let socket = SocketIOClient(
            url: testURL,
            reconnect: .disabled,
            taskFactory: { _, _ in task },
            clock: clock
        )

        // Subscribe before connecting - statusUpdates() only emits the current status
        // immediately on subscription, so subscribing after the transitions already
        // happened would only ever see .connected and then hang waiting for a further
        // transition that never comes.
        let statusStream = await socket.statusUpdates()
        await socket.connect()
        await performHandshake(on: task)

        var iterator = statusStream.makeAsyncIterator()
        _ = await iterator.next() // .disconnected
        _ = await iterator.next() // .connecting
        _ = await iterator.next() // .connected

        // Send several frames instead of letting the heartbeat deadline elapse - each
        // one resets the watchdog before it can fire.
        for _ in 0..<3 {
            let sentBefore = task.sentMessages.count
            task.inject(text: "2") // Engine.IO PING - client replies "3" (PONG)
            var attempts = 0
            while task.sentMessages.count <= sentBefore && attempts < 100 {
                await Task.yield()
                attempts += 1
            }
        }

        #expect(task.cancelCount == 0)
    }

    @Test("No inbound frames within pingInterval + pingTimeout triggers a reconnect attempt")
    func heartbeatTimeoutTriggersReconnect() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        nonisolated(unsafe) var taskIndex = 0
        let tasks = [task1, task2]
        let clock = ManualSleepClock()
        let socket = SocketIOClient(
            url: testURL,
            reconnect: .init(enabled: true, initialDelay: .milliseconds(1), maxDelay: .seconds(1), multiplier: 2.0),
            taskFactory: { _, _ in
                let t = tasks[taskIndex]
                taskIndex += 1
                return t
            },
            clock: clock
        )

        let statusStream = await socket.statusUpdates()
        await socket.connect()
        await performHandshake(on: task1)

        var iterator = statusStream.makeAsyncIterator()
        _ = await iterator.next() // .disconnected
        _ = await iterator.next() // .connecting
        _ = await iterator.next() // .connected

        // Simulate the heartbeat deadline elapsing with no further frames - this cancels
        // task1, whose receive() then throws, routing through the normal disconnect path.
        await waitForClockQuiescence(clock)
        await clock.advanceLatest()

        let disconnected = await iterator.next()
        #expect(disconnected == .disconnected)

        // Let the reconnect delay elapse so the loop attempts task2.
        await waitForClockQuiescence(clock)
        await clock.advanceLatest()
        _ = await iterator.next() // .connecting

        await performHandshake(on: task2)
        _ = await iterator.next() // .connected

        #expect(task1.resumeCount == 1)
        #expect(task1.cancelCount == 1)
        #expect(task2.resumeCount == 1)

        await socket.invalidate()
    }

    // MARK: - Connect Error

    @Test("CONNECT_ERROR (44) sets status to .failed with the server's message")
    func connectErrorSetsFailedStatusWithReason() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        _ = await statusIterator.next() // .connecting

        task.inject(text: #"44{"message":"Not authorized"}"#)

        let status = await statusIterator.next()
        #expect(status == .failed(reason: "Not authorized"))
    }

    @Test("CONNECT_ERROR (44) with no payload falls back to a generic reason")
    func connectErrorWithNoPayloadUsesGenericReason() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        _ = await statusIterator.next() // .connecting

        task.inject(text: "44")

        let status = await statusIterator.next()
        #expect(status == .failed(reason: "Connection rejected by server"))
    }

    @Test("CONNECT_ERROR (44) with malformed JSON falls back to a generic reason without crashing")
    func connectErrorWithMalformedJSONUsesGenericReason() async {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        _ = await statusIterator.next() // .connecting

        // Has a brace, so it reaches the JSONSerialization path, but is not valid JSON.
        task.inject(text: "44{not valid json")

        let status = await statusIterator.next()
        #expect(status == .failed(reason: "Connection rejected by server"))
    }

    @Test("An unrecognized Socket.IO packet type is ignored without disrupting the connection")
    func unrecognizedSocketIOPacketTypeIsIgnored() async throws {
        let task = MockWebSocketTask()
        let socket = makeSocket(tasks: [task])

        let statusStream = await socket.statusUpdates()
        await socket.connect()
        await performHandshake(on: task)

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        _ = await statusIterator.next() // .connecting
        _ = await statusIterator.next() // .connected

        // Socket.IO ACK (43) - not currently handled, should be ignored rather than
        // crashing or disrupting the connection.
        task.inject(text: "43[1,{}]")

        // The connection is still usable: a subsequent event still arrives.
        let eventStream = await socket.events(for: PingEvent.self)
        task.inject(text: #"42["test_ping",{"message":"hi"}]"#)
        let event = await awaitNextEvent(from: eventStream)
        #expect(event == PingEvent.Schema(message: "hi"))

        #expect(task.cancelCount == 0)
    }

    @Test("CONNECT_ERROR (44) does not trigger automatic reconnection even when reconnect is enabled")
    func connectErrorSuppressesAutomaticReconnect() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        nonisolated(unsafe) var taskIndex = 0
        let tasks = [task1, task2]
        let socket = SocketIOClient(
            url: testURL,
            reconnect: .init(enabled: true, initialDelay: .milliseconds(1), maxDelay: .seconds(1), multiplier: 2.0),
            taskFactory: { _, _ in
                let t = tasks[taskIndex]
                taskIndex += 1
                return t
            }
        )

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        _ = await statusIterator.next() // .connecting

        task1.inject(text: #"44{"message":"Not authorized"}"#)
        let status = await statusIterator.next()
        #expect(status == .failed(reason: "Not authorized"))

        // Give an (incorrect) reconnect loop a generous number of scheduler turns to run
        // before asserting it never did - no real time elapses since the loop's exit
        // check happens before its delay, so this is not a timing-sensitive wait.
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(task1.resumeCount == 1)
        #expect(task2.resumeCount == 0)
    }

    @Test("connect() can be called again after a CONNECT_ERROR to retry with fresh credentials")
    func connectAfterConnectErrorStartsANewConnection() async {
        let task1 = MockWebSocketTask()
        let task2 = MockWebSocketTask()
        let socket = makeSocket(tasks: [task1, task2])

        let statusStream = await socket.statusUpdates()
        await socket.connect()

        var statusIterator = statusStream.makeAsyncIterator()
        _ = await statusIterator.next() // .disconnected
        _ = await statusIterator.next() // .connecting

        task1.inject(text: "44")
        _ = await statusIterator.next() // .failed

        await socket.connect()
        _ = await statusIterator.next() // .connecting

        await performHandshake(on: task2)
        _ = await statusIterator.next() // .connected

        #expect(task1.resumeCount == 1)
        #expect(task2.resumeCount == 1)

        await socket.invalidate()
    }
}

// MARK: - SocketEmptyBody Tests

@Suite("SocketEmptyBody Tests", .timeLimit(.minutes(1)))
struct SocketEmptyBodyTests {

    @Test("init() creates an instance")
    func initCreatesInstance() {
        _ = SocketEmptyBody()
    }

    @Test("Decodable from empty JSON object")
    func decodableFromEmptyObject() throws {
        let data = Data("{}".utf8)
        _ = try JSONDecoder().decode(SocketEmptyBody.self, from: data)
    }

    @Test("Decodable from JSON array (no-payload event frame data)")
    func decodableFromEmptyArrayElement() throws {
        // Socket.IO no-payload events supply Data("{}") as the payload default
        let data = Data("{}".utf8)
        let body = try JSONDecoder().decode(SocketEmptyBody.self, from: data)
        _ = body
    }
}
