//
//  SocketIOClient.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-06-22.
//

import Foundation

/// Abstracts `URLSessionWebSocketTask` for test injection.
public protocol WebSocketTask: AnyObject {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
}

extension URLSessionWebSocketTask: WebSocketTask {}

/// Swift 6 actor implementing the Socket.IO 4.x wire protocol over URLSessionWebSocketTask.
///
/// The public API is entirely typed via `SocketEvent`. Raw frame encoding/decoding is an
/// implementation detail — no consumer ever sees event names as strings or payloads as `Data`.
///
/// Event streams registered via `events(for:)` survive `disconnect()`/`reconnect(to:)` cycles.
/// They only finish when `invalidate()` is called.
public actor SocketIOClient {

    // MARK: - Public Types

    /// Connection state of the socket.
    public enum Status: Sendable, Equatable {
        /// No active connection.
        case disconnected
        /// TCP connection established; Socket.IO handshake in progress.
        case connecting
        /// Socket.IO handshake complete; events can be sent and received.
        case connected
    }

    /// Controls automatic reconnection after an unexpected disconnection.
    public struct ReconnectPolicy: Sendable {
        /// Whether reconnection is attempted at all.
        public var enabled: Bool
        /// Delay before the first reconnection attempt. Must be ≥ 1 second for backoff to work correctly.
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

    private var status: Status = .disconnected
    private var isDisconnecting = false
    private var connectionLoopTask: Task<Void, Never>?
    private var currentTask: (any WebSocketTask)?

    // Per-event-name fan-out. Keyed by SocketEvent.name so each typed stream receives only its events.
    // These persist across disconnect/reconnect — consumers never need to re-subscribe.
    private var eventContinuations: [String: [UUID: AsyncStream<Data>.Continuation]] = [:]
    private var statusContinuations: [UUID: AsyncStream<Status>.Continuation] = [:]
    private var pipeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Init

    /// Creates a `SocketIOClient`.
    ///
    /// - Parameters:
    ///   - url: The Socket.IO WebSocket URL. Use `webSocketURL(for:)` to derive it from an HTTP/HTTPS server URL.
    ///   - session: The underlying `URLSession`. Defaults to `URLSession.shared`.
    ///   - reconnect: Reconnection policy. Defaults to exponential backoff with a 1–15s range.
    public init(url: URL, session: URLSession = .shared, reconnect: ReconnectPolicy = .init()) {
        self.url = url
        self.urlSession = session
        self.reconnectPolicy = reconnect
        self.taskFactory = nil
    }

    /// Internal initializer for unit tests — inject a custom WebSocketTask factory.
    init(
        url: URL,
        session: URLSession = .shared,
        reconnect: ReconnectPolicy = .init(),
        taskFactory: @escaping @Sendable (URL, URLSession) -> any WebSocketTask
    ) {
        self.url = url
        self.urlSession = session
        self.reconnectPolicy = reconnect
        self.taskFactory = taskFactory
    }

    // MARK: - Connection

    /// Open connection. No-ops if already connecting or connected.
    public func connect() async {
        guard status == .disconnected else { return }
        isDisconnecting = false
        connectionLoopTask = Task { await self.connectionLoop() }
    }

    /// Close the connection. Registered event and status streams are preserved for reconnect.
    public func disconnect() {
        isDisconnecting = true
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        currentTask?.cancel(with: .goingAway, reason: nil)
        currentTask = nil
        setStatus(.disconnected)
    }

    /// Switch to a new URL and reconnect, preserving all registered event streams.
    public func reconnect(to newURL: URL) async {
        url = newURL
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        currentTask?.cancel(with: .goingAway, reason: nil)
        currentTask = nil
        setStatus(.disconnected)
        connectionLoopTask = Task { await self.connectionLoop() }
    }

    /// Fully tear down — closes the connection and finishes all registered streams.
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
        try await sendText(#"42["\#(E.name)",\#(json)]"#)
    }

    /// Emit a typed event with no payload.
    public func emit<E: SocketEvent>(_ type: E.Type) async throws where E.Schema == SocketEmptyBody {
        try await sendText(#"42["\#(E.name)"]"#)
    }

    // MARK: - Typed Streams

    /// Returns a typed `AsyncStream` for the given event type. Multiple independent consumers
    /// are supported — each call registers a new stream. All receive the same events.
    /// The stream persists across disconnect/reconnect cycles.
    public func events<E: SocketEvent>(for type: E.Type) -> AsyncStream<E.Schema> {
        let id = UUID()
        let (dataStream, dataContinuation) = AsyncStream<Data>.makeStream()

        eventContinuations[E.name, default: [:]][id] = dataContinuation

        dataContinuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeEventContinuation(id, name: E.name) }
        }

        let (typedStream, typedContinuation) = AsyncStream<E.Schema>.makeStream()
        let pipeTask = Task {
            for await data in dataStream {
                guard let value = try? JSONDecoder().decode(E.Schema.self, from: data) else {
                    continue
                }
                typedContinuation.yield(value)
            }
            typedContinuation.finish()
        }
        pipeTasks[id] = pipeTask
        typedContinuation.onTermination = { _ in dataContinuation.finish() }

        return typedStream
    }

    /// Returns a stream of connection status changes. Emits the current status immediately.
    /// The stream persists across disconnect/reconnect cycles.
    public func statusUpdates() -> AsyncStream<Status> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Status>.makeStream()
        statusContinuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeStatusContinuation(id) }
        }
        return stream
    }

    // MARK: - Socket.IO URL Construction

    /// Builds the Socket.IO 4.x WebSocket URL from an HTTP/HTTPS server base URL.
    public static func webSocketURL(for serverURL: URL) -> URL? {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/socket.io/"
        components?.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
        return components?.url
    }

    // MARK: - Private: Connection Loop

    private func connectionLoop() async {
        var delay: Duration?

        while !isDisconnecting && !Task.isCancelled {
            if let duration = delay {
                do { try await Task.sleep(for: duration) } catch { return }
            }

            setStatus(.connecting)
            let task = makeWebSocketTask()
            currentTask = task
            task.resume()

            var shouldReconnect = false
            while !isDisconnecting && !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    await handleMessage(message)
                } catch {
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

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard case .string(let text) = message else { return }

        if text.hasPrefix("0") {
            // Engine.IO OPEN — send Socket.IO CONNECT to default namespace
            rnLog(.socket, "open")
            try? await currentTask?.send(.string("40"))
            return
        }

        if text == "2" {
            // Engine.IO PING — respond with PONG
            rnLog(.socket, "ping")
            try? await currentTask?.send(.string("3"))
            return
        }

        if text.hasPrefix("40") {
            // Socket.IO CONNECT ack
            rnLog(.socket, "connect")
            setStatus(.connected)
            return
        }

        if text.hasPrefix("42"), let (name, payload) = parseEvent(text) {
            rnLog(.socket, "event: \(name)")
            let data = payload ?? Data("{}".utf8)
            if let conts = eventContinuations[name] {
                for cont in conts.values { cont.yield(data) }
            }
        }
    }

    private func parseEvent(_ text: String) -> (name: String, payload: Data?)? {
        let json = String(text.dropFirst(2))
        guard
            let data = json.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let name = array.first as? String
        else { return nil }

        let payload: Data? = array.count > 1
            ? try? JSONSerialization.data(withJSONObject: array[1], options: .fragmentsAllowed)
            : nil

        return (name, payload)
    }

    // MARK: - Private: Helpers

    private func sendText(_ text: String) async throws {
        guard let task = currentTask else { throw SocketIOError.notConnected }
        try await task.send(.string(text))
    }

    private func setStatus(_ newStatus: Status) {
        status = newStatus
        for cont in statusContinuations.values { cont.yield(newStatus) }
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
}

/// Errors thrown by `SocketIOClient`.
public enum SocketIOError: Error, Sendable {
    /// An emit was attempted while the socket was not connected.
    case notConnected
    /// The event payload could not be serialized to a UTF-8 JSON string.
    case encodingFailed
}
