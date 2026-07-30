//
//  SocketIOClient.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-06-22.
//

import Foundation
import OSLog

/// Abstracts `URLSessionWebSocketTask` for test injection.
protocol WebSocketTask: AnyObject, Sendable {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
}

extension URLSessionWebSocketTask: WebSocketTask {}

/// Swift 6 actor implementing the Socket.IO 4.x wire protocol over URLSessionWebSocketTask.
///
/// The public API is entirely typed via `SocketEvent`. Raw frame encoding/decoding is an
/// implementation detail - no consumer ever sees event names as strings or payloads as `Data`.
///
/// Event streams registered via `events(for:)` survive `disconnect()`/`reconnect(to:)` cycles.
/// They only finish when `invalidate()` is called.
public actor SocketIOClient {

    // MARK: - Public Types

    /// Connection state of the socket.
    public typealias Status = SocketConnectionStatus

    /// Controls automatic reconnection after an unexpected disconnection.
    public struct ReconnectPolicy: Sendable {
        /// Whether reconnection is attempted at all.
        public var enabled: Bool
        /// Delay before the first reconnection attempt.
        public var initialDelay: Duration
        /// Upper bound on the backoff delay.
        public var maxDelay: Duration
        /// Multiplier applied to the current delay after each failed attempt.
        public var multiplier: Double

        /// Creates a reconnect policy with exponential backoff.
        public init(
            enabled: Bool = true,
            initialDelay: Duration = .seconds(1),
            maxDelay: Duration = .seconds(15),
            multiplier: Double = 2.0
        ) {
            self.enabled = enabled
            self.initialDelay = initialDelay
            self.maxDelay = maxDelay
            self.multiplier = multiplier
        }

        /// A policy that performs no reconnection.
        public static let disabled = ReconnectPolicy(enabled: false)
    }

    // MARK: - Private State

    private var url: URL
    private let urlSession: URLSession
    private let reconnectPolicy: ReconnectPolicy
    private let taskFactory: (@Sendable (URL, URLSession) -> any WebSocketTask)?
    let clock: any SleepClock

    private var status: Status = .disconnected
    private var isDisconnecting = false
    private var connectionLoopTask: Task<Void, Never>?
    var currentTask: (any WebSocketTask)?
    var connectionGeneration: UInt64 = 0

    /// Engine.IO heartbeat parameters from the current connection's `open` handshake.
    /// Reset to these defaults at the start of every connection attempt; overwritten
    /// with the server's actual values once the `open` payload is parsed.
    var pingInterval: Duration = .seconds(25)
    var pingTimeout: Duration = .seconds(20)

    /// Watches for the absence of any inbound frame within `pingInterval + pingTimeout`.
    /// Reset on every inbound frame; a real Socket.IO server pings within `pingInterval`,
    /// so any silence longer than the combined window means the connection is half-open.
    var heartbeatTask: Task<Void, Never>?

    // Per-event-name fan-out. Keyed by SocketEvent.name so each typed stream receives only its events.
    // These persist across disconnect/reconnect - consumers never need to re-subscribe.
    var eventContinuations: [String: [UUID: AsyncStream<Data>.Continuation]] = [:]
    private var statusContinuations: [UUID: AsyncStream<Status>.Continuation] = [:]
    private var pipeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Init

    /// Creates a `SocketIOClient`.
    ///
    /// - Parameters:
    ///   - url: The Socket.IO WebSocket URL. Use `webSocketURL(for:)` to derive it from an HTTP/HTTPS server URL.
    ///   - session: The underlying `URLSession`. Defaults to `URLSession.shared`.
    ///   - reconnect: Reconnection policy. Defaults to exponential backoff with a 1–15s range.
    public init(
        url: URL,
        session: URLSession = .shared,
        reconnect: ReconnectPolicy = .init()
    ) {
        self.url = url
        self.urlSession = session
        self.reconnectPolicy = reconnect
        self.taskFactory = nil
        self.clock = SystemSleepClock()
    }

    /// Internal initializer for unit tests - inject a custom WebSocketTask factory and,
    /// optionally, a replacement clock so reconnect and heartbeat timing are deterministic
    /// rather than tied to the wall clock.
    init(
        url: URL,
        session: URLSession = .shared,
        reconnect: ReconnectPolicy = .init(),
        taskFactory: @escaping @Sendable (URL, URLSession) -> any WebSocketTask,
        clock: any SleepClock = SystemSleepClock()
    ) {
        self.url = url
        self.urlSession = session
        self.reconnectPolicy = reconnect
        self.taskFactory = taskFactory
        self.clock = clock
    }

    // MARK: - Connection

    /// Open connection. No-ops if already connecting or connected. Can be called again
    /// after a `.failed` status, for example once fresh credentials are available.
    public func connect() async {
        guard canStartNewConnection else { return }
        isDisconnecting = false
        connectionGeneration &+= 1
        let generation = connectionGeneration
        connectionLoopTask = Task { await self.connectionLoop(generation: generation) }
    }

    /// Close the connection. Registered event and status streams are preserved for reconnect.
    public func disconnect() {
        isDisconnecting = true
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        currentTask?.cancel(with: .goingAway, reason: nil)
        currentTask = nil
        setStatus(.disconnected)
    }

    /// Switch to a new URL and reconnect, preserving all registered event streams.
    public func reconnect(to newURL: URL) async {
        url = newURL
        isDisconnecting = false
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        currentTask?.cancel(with: .goingAway, reason: nil)
        currentTask = nil
        setStatus(.disconnected)
        connectionGeneration &+= 1
        let generation = connectionGeneration
        connectionLoopTask = Task { await self.connectionLoop(generation: generation) }
    }

    /// Fully tear down - closes the connection and finishes all registered streams.
    public func invalidate() {
        disconnect()
        finishAllContinuations()
    }

    // MARK: - Typed Emit

    /// Emit a typed event with an Encodable payload.
    public func emit<E: SocketEvent>(
        _ type: E.Type, _ payload: E.Schema
    ) async throws where E.Schema: Encodable & Sendable {
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SocketIOError.encodingFailed
        }
        try await sendText(#"\#(SocketIOPacketType.event.enginePrefixedWireValue)["\#(E.name)",\#(json)]"#)
    }

    /// Emit a typed event with no payload.
    public func emit<E: SocketEvent>(_ type: E.Type) async throws where E.Schema == SocketEmptyBody {
        try await sendText(#"\#(SocketIOPacketType.event.enginePrefixedWireValue)["\#(E.name)"]"#)
    }

    // MARK: - Typed Streams

    /// Returns a typed `AsyncStream` for the given event type. Multiple independent consumers
    /// are supported - each call registers a new stream. All receive the same events.
    /// The stream persists across disconnect/reconnect cycles.
    ///
    /// - Parameter bufferingPolicy: Governs both the raw and decoded buffers backing the
    ///   stream. Defaults to `.bufferingNewest(64)` - a consumer that falls behind drops the
    ///   oldest unread events rather than growing without bound. Pass `.unbounded` to restore
    ///   the previous behavior, or a smaller `.bufferingNewest(n)` for event types where only
    ///   the latest value is meaningful.
    public func events<E: SocketEvent>(
        for type: E.Type,
        bufferingPolicy: AsyncStream<E.Schema>.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> AsyncStream<E.Schema> {
        let id = UUID()
        let (dataStream, dataContinuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: Self.mapBufferingPolicy(bufferingPolicy)
        )

        eventContinuations[E.name, default: [:]][id] = dataContinuation

        dataContinuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeEventContinuation(id, name: E.name) }
        }

        let (typedStream, typedContinuation) = AsyncStream<E.Schema>.makeStream(bufferingPolicy: bufferingPolicy)
        let pipeTask = Task {
            for await data in dataStream {
                guard let value = try? JSONDecoder().decode(E.Schema.self, from: data) else {
                    continue
                }
                if case .dropped = typedContinuation.yield(value) {
                    Logger.socket.error("decoded event dropped due to buffering policy: \(E.name, privacy: .private)")
                }
            }
            typedContinuation.finish()
        }
        pipeTasks[id] = pipeTask
        typedContinuation.onTermination = { _ in dataContinuation.finish() }

        return typedStream
    }

    /// Converts a `BufferingPolicy` between `AsyncStream` specializations. The enum's cases
    /// don't depend on `Element`, but each specialization is a distinct nominal type.
    private static func mapBufferingPolicy<From, To>(
        _ policy: AsyncStream<From>.Continuation.BufferingPolicy
    ) -> AsyncStream<To>.Continuation.BufferingPolicy {
        switch policy {
        case .unbounded: return .unbounded
        case .bufferingOldest(let limit): return .bufferingOldest(limit)
        case .bufferingNewest(let limit): return .bufferingNewest(limit)
        @unknown default: return .unbounded
        }
    }

    /// Returns a stream of connection status changes. Emits the current status immediately.
    /// The stream persists across disconnect/reconnect cycles.
    ///
    /// Uses a fixed `.bufferingNewest(1)` policy - only the current connection state is ever
    /// meaningful, so a backlog of stale states is dropped rather than retained.
    public func statusUpdates() -> AsyncStream<SocketConnectionStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SocketConnectionStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        statusContinuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeStatusContinuation(id) }
        }
        return stream
    }

    // MARK: - Socket.IO URL Construction

    /// Builds the Socket.IO 4.x WebSocket URL from an HTTP/HTTPS server base URL.
    ///
    /// Joins `path` onto the server URL's existing path rather than discarding it, so a
    /// server hosted under a prefix (for example behind a reverse proxy at
    /// `https://example.com/api/v2`) resolves to `wss://example.com/api/v2/socket.io/...`.
    /// Any existing query items on `serverURL` are preserved alongside `EIO` and `transport`.
    ///
    /// - Parameters:
    ///   - serverURL: The HTTP/HTTPS base URL of the Socket.IO server.
    ///   - path: The Socket.IO endpoint path, joined onto `serverURL`'s path. Defaults to
    ///     `"socket.io"`, matching Socket.IO's own default `path` client option.
    public static func webSocketURL(for serverURL: URL, path: String = "socket.io") -> URL? {
        SocketIOURL.webSocketURL(for: serverURL, path: path)
    }

    // MARK: - Private: Connection Loop

    private func connectionLoop(generation: UInt64) async {
        var delay: Duration?

        while shouldContinueConnectionLoop(for: generation) {
            if let duration = delay {
                do { try await clock.sleep(for: duration) } catch { return }
            }

            guard generation == connectionGeneration else { return }
            setStatus(.connecting)
            pingInterval = .seconds(25)
            pingTimeout = .seconds(20)
            let task = makeWebSocketTask()
            currentTask = task
            task.resume()
            resetHeartbeat(generation: generation)

            var shouldReconnect = false
            while shouldContinueConnectionLoop(for: generation) {
                do {
                    let message = try await task.receive()
                    await handleMessage(message, generation: generation)
                } catch {
                    guard generation == connectionGeneration else { return }
                    heartbeatTask?.cancel()
                    heartbeatTask = nil
                    if isDisconnecting || Task.isCancelled { return }
                    setStatus(.disconnected)
                    guard reconnectPolicy.enabled else { return }
                    shouldReconnect = true
                    break
                }
            }

            guard shouldReconnect else { return }
            delay = nextDelay(after: delay)
        }
    }

    // MARK: - Private: Frame Handling

    private func handleMessage(
        _ message: URLSessionWebSocketTask.Message,
        generation: UInt64
    ) async {
        guard generation == connectionGeneration else { return }

        guard case .string(let text) = message else {
            resetHeartbeat(generation: generation)
            Logger.socket.debug("ignored non-text WebSocket frame")
            return
        }

        guard let frame = ParsedEngineIOFrame.parse(text) else {
            resetHeartbeat(generation: generation)
            Logger.socket.debug("ignored unrecognized Engine.IO frame")
            return
        }

        if frame.engineIOType == .open {
            // Engine.IO OPEN - parse the server's heartbeat timing before arming the
            // watchdog, so the deadline reflects it immediately, then send Socket.IO
            // CONNECT to the default namespace
            Logger.socket.debug("open")
            parseOpenPayload(text)
            resetHeartbeat(generation: generation)
            try? await currentTask?.send(.string(SocketIOPacketType.connect.enginePrefixedWireValue))
            return
        }

        resetHeartbeat(generation: generation)

        switch (frame.engineIOType, frame.socketIOType) {
        case (.ping, _) where frame.payload.isEmpty:
            // Engine.IO PING - respond with PONG
            Logger.socket.debug("ping")
            try? await currentTask?.send(.string(EngineIOPacketType.pong.wireValue))

        case (.message, let socketIOType):
            await handleSocketIOPacket(socketIOType, payload: frame.payload)

        default:
            Logger.socket.debug(
                "ignored unhandled Engine.IO packet \(String(describing: frame.engineIOType), privacy: .public)"
            )
        }
    }

    // MARK: - Private: Helpers

    private func sendText(_ text: String) async throws {
        guard let task = currentTask else { throw SocketIOError.notConnected }
        try await task.send(.string(text))
    }

    func setStatus(_ newStatus: Status) {
        status = newStatus
        for cont in statusContinuations.values {
            if case .dropped = cont.yield(newStatus) {
                Logger.socket.error("status update dropped due to buffering policy")
            }
        }
    }

    /// Tears down the current connection attempt after a server-rejected connection
    /// (`CONNECT_ERROR`) and suppresses automatic reconnection - the same credentials
    /// would only be rejected again. `connect()` or `reconnect(to:)` can still be called
    /// explicitly afterward, for example once fresh credentials are available.
    func failConnection(reason: String) {
        isDisconnecting = true
        currentTask?.cancel(with: .goingAway, reason: nil)
        currentTask = nil
        setStatus(.failed(reason: reason))
    }

    private func finishAllContinuations() {
        for perName in eventContinuations.values {
            for cont in perName.values { cont.finish() }
        }
        eventContinuations = [:]
        for cont in statusContinuations.values { cont.finish() }
        statusContinuations = [:]
        for task in pipeTasks.values { task.cancel() }
        pipeTasks = [:]
    }

    private func makeWebSocketTask() -> any WebSocketTask {
        taskFactory?(url, urlSession) ?? urlSession.webSocketTask(with: url)
    }

    private func nextDelay(after current: Duration?) -> Duration {
        guard let current else { return reconnectPolicy.initialDelay }
        let seconds = Double(current.components.seconds) + Double(current.components.attoseconds) / 1e18
        return min(.seconds(seconds * reconnectPolicy.multiplier), reconnectPolicy.maxDelay)
    }

    private func removeEventContinuation(_ id: UUID, name: String) {
        eventContinuations[name]?.removeValue(forKey: id)
        if eventContinuations[name]?.isEmpty == true {
            eventContinuations.removeValue(forKey: name)
        }
        pipeTasks[id]?.cancel()
        pipeTasks.removeValue(forKey: id)
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }

    private func shouldContinueConnectionLoop(for generation: UInt64) -> Bool {
        generation == connectionGeneration && !isDisconnecting && !Task.isCancelled
    }

    private var canStartNewConnection: Bool {
        switch status {
        case .disconnected, .failed:
            return true

        case .connecting, .connected:
            return false
        }
    }
}

/// Errors thrown by `SocketIOClient`.
public enum SocketIOError: Error, Sendable {
    /// An emit was attempted while the socket was not connected.
    case notConnected
    /// The event payload could not be serialized to a UTF-8 JSON string.
    case encodingFailed
}

extension SocketIOClient: SocketClient {}
