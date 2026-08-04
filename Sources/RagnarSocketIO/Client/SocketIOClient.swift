import Foundation
import OSLog
import RagnarWebSocket

/// An Engine.IO 4 and Socket.IO protocol 5 client over direct WebSocket transport.
public actor SocketIOClient: SocketClient {
    let webSocket: any WebSocketClient
    let decoder: SocketEventDecoder
    let encoder: SocketEventEncoder
    let reconnectPolicy: ReconnectPolicy
    let namespaceTimeout: Duration
    let clock: any SocketIOClock
    let randomSource: any SocketIORandomSource

    var generation: UInt64 = 0
    var endpoint: SocketIOEndpoint?
    var status: SocketConnectionStatus = .disconnected
    var connectionTask: Task<Void, Never>?
    var pendingCloseTask: Task<Void, Never>?
    var heartbeatTask: Task<Void, Never>?
    var namespaceTimeoutTask: Task<Void, Never>?
    var isExplicitlyDisconnected = false
    var isInvalidated = false
    var maximumPayload: Int?
    var heartbeatDeadline: Duration?
    var forcedFailure: (generation: UInt64, failure: LifecycleFailure)?
    var eventSubscriptions: [String: [UUID: SocketEventContinuation]] = [:]
    var statusContinuations: [UUID: AsyncStream<SocketConnectionStatus>.Continuation] = [:]

    /// Creates a Socket.IO client without starting a connection.
    ///
    /// The decoder and encoder values are factories. The client creates a new Foundation coder for each event decode or
    /// emission. `namespaceTimeout` must be positive.
    public init(
        webSocket: any WebSocketClient = URLSessionWebSocketClient(),
        decoder: SocketEventDecoder = .default,
        encoder: SocketEventEncoder = .default,
        reconnectPolicy: ReconnectPolicy = .default,
        namespaceTimeout: Duration = .seconds(45)
    ) {
        precondition(namespaceTimeout > .zero, "Namespace timeout must be positive")
        self.webSocket = webSocket
        self.decoder = decoder
        self.encoder = encoder
        self.reconnectPolicy = reconnectPolicy
        self.namespaceTimeout = namespaceTimeout
        clock = ContinuousSocketIOClock()
        randomSource = SystemSocketIORandomSource()
    }

    init(
        webSocket: any WebSocketClient,
        decoder: SocketEventDecoder = .default,
        encoder: SocketEventEncoder = .default,
        reconnectPolicy: ReconnectPolicy = .default,
        namespaceTimeout: Duration = .seconds(45),
        clock: any SocketIOClock,
        randomSource: any SocketIORandomSource
    ) {
        self.webSocket = webSocket
        self.decoder = decoder
        self.encoder = encoder
        self.reconnectPolicy = reconnectPolicy
        self.namespaceTimeout = namespaceTimeout
        self.clock = clock
        self.randomSource = randomSource
    }

    /// Validates the endpoint and starts a new connection generation.
    ///
    /// The method returns after scheduling the lifecycle task. Observe `statusUpdates()` for handshake completion. A
    /// different valid endpoint replaces the active generation; an invalid endpoint leaves it unchanged.
    public func connect(to endpoint: SocketIOEndpoint) throws {
        guard !isInvalidated else { throw SocketIOError.invalidated }
        let request = try endpoint.resolve()
        if self.endpoint == endpoint, status.isActive {
            return
        }

        generation &+= 1
        let connectionGeneration = generation
        connectionTask?.cancel()
        heartbeatTask?.cancel()
        namespaceTimeoutTask?.cancel()
        forcedFailure = nil
        maximumPayload = nil
        heartbeatDeadline = nil
        self.endpoint = endpoint
        isExplicitlyDisconnected = false
        setStatus(.connecting)
        Logger.socketIO.debug(
            """
            Starting generation \(connectionGeneration, privacy: .public) \
            for \(request.url?.absoluteString ?? "no URL", privacy: .private)
            """
        )
        connectionTask = Task {
            await self.runConnectionLoop(generation: connectionGeneration, request: request)
        }
    }

    /// Closes the active connection and publishes `.disconnected` without finishing subscriptions.
    public func disconnect() {
        guard !isInvalidated else { return }
        generation &+= 1
        isExplicitlyDisconnected = true
        cancelLifecycleTasks()
        maximumPayload = nil
        heartbeatDeadline = nil
        forcedFailure = nil
        setStatus(.disconnected)
        Logger.socketIO.debug("Disconnected by the app at generation \(self.generation, privacy: .public)")
        pendingCloseTask = Task { await webSocket.close(code: .normalClosure, reason: nil) }
    }

    /// Permanently closes the client, publishes `.invalidated`, and finishes every subscription.
    public func invalidate() {
        guard !isInvalidated else { return }
        generation &+= 1
        isInvalidated = true
        isExplicitlyDisconnected = true
        cancelLifecycleTasks()
        maximumPayload = nil
        heartbeatDeadline = nil
        forcedFailure = nil
        Logger.socketIO.debug(
            """
            Invalidated at generation \(self.generation, privacy: .public), \
            finishing \(self.eventSubscriptions.count, privacy: .public) event subscriptions
            """
        )
        pendingCloseTask = Task { await webSocket.close(code: .normalClosure, reason: nil) }

        for subscriptions in eventSubscriptions.values {
            for continuation in subscriptions.values {
                continuation.finish(throwing: SocketIOError.invalidated)
            }
        }
        eventSubscriptions.removeAll()
        setStatus(.invalidated)
        for continuation in statusContinuations.values {
            continuation.finish()
        }
        statusContinuations.removeAll()
    }

    /// Encodes and emits one event payload.
    /// - Throws: `SocketIOError.notConnected`, `SocketIOError.messageTooLarge`, an event encoding error, or a transport
    ///   error.
    public func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type,
        _ payload: Event.Schema
    ) async throws {
        guard !isInvalidated else { throw SocketIOError.invalidated }
        guard status == .connected, maximumPayload != nil else {
            throw SocketIOError.notConnected
        }

        let arguments = try Event.encode(payload, using: encoder.makeEncoder())
        try await emit(name: Event.name, arguments: arguments)
    }

    /// Emits an event with no arguments.
    public func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type
    ) async throws where Event.Schema == SocketEmptyBody {
        try await emit(event, SocketEmptyBody())
    }

    /// Creates an independent typed event stream.
    ///
    /// Subscriptions persist across disconnect and reconnect. Event decoding occurs when the iterator requests its next
    /// value. A decoding failure or terminating overflow affects only this subscription.
    public func events<Event: SocketEvent>(
        for event: Event.Type,
        policy: SocketStreamPolicy? = nil
    ) -> SocketEventStream<Event> {
        let subscriptionID = UUID()
        let subscription = SocketEventStream<Event>.make(
            policy: policy ?? Event.defaultStreamPolicy,
            decoder: decoder,
            onTermination: { [weak self] in
                Task { await self?.removeEventSubscription(id: subscriptionID, eventName: Event.name) }
            }
        )

        if isInvalidated {
            subscription.continuation.finish(throwing: SocketIOError.invalidated)
        } else {
            eventSubscriptions[Event.name, default: [:]][subscriptionID] = subscription.continuation
        }
        return subscription.stream
    }

    /// Creates a newest-value stream that emits the current status immediately.
    ///
    /// The stream retains one pending status. A slow consumer may skip intermediate states.
    public func statusUpdates() -> AsyncStream<SocketConnectionStatus> {
        let subscriptionID = UUID()
        let (stream, continuation) = AsyncStream<SocketConnectionStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.yield(status)
        if isInvalidated {
            continuation.finish()
        } else {
            statusContinuations[subscriptionID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStatusSubscription(id: subscriptionID) }
            }
        }
        return stream
    }

    func emit(name: String, arguments: [SocketIOArgument]) async throws {
        guard status == .connected, let maximumPayload else {
            throw SocketIOError.notConnected
        }
        let connectionGeneration = generation
        let socketPacket = SocketIOPacket.event(
            namespace: "/",
            acknowledgementID: nil,
            name: name,
            arguments: arguments
        )
        let socketPayload = try SocketIOCodec.encode(socketPacket)
        let enginePacket = EngineIOPacket.message(socketPayload)
        do {
            try enginePacket.validateMessageSize(maximum: maximumPayload)
        } catch SocketIOProtocolError.messageExceedsMaximumPayload(let limit, let actual) {
            throw SocketIOError.messageTooLarge(limit: limit, actual: actual)
        }

        do {
            try await webSocket.send(.text(try EngineIOCodec.encode(enginePacket)))
        } catch {
            await failGenerationFromSend(connectionGeneration, error: error)
            throw error
        }
    }

    func setStatus(_ newStatus: SocketConnectionStatus) {
        guard status != newStatus else { return }
        status = newStatus
        for continuation in statusContinuations.values {
            continuation.yield(newStatus)
        }
    }

    func removeEventSubscription(id: UUID, eventName: String) {
        eventSubscriptions[eventName]?[id] = nil
        if eventSubscriptions[eventName]?.isEmpty == true {
            eventSubscriptions[eventName] = nil
        }
    }

    func removeStatusSubscription(id: UUID) {
        statusContinuations[id] = nil
    }

    func cancelLifecycleTasks() {
        connectionTask?.cancel()
        connectionTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        namespaceTimeoutTask?.cancel()
        namespaceTimeoutTask = nil
    }
}

private extension SocketConnectionStatus {
    var isActive: Bool {
        switch self {
        case .connecting, .connected, .reconnecting:
            true

        case .disconnected, .failed, .invalidated:
            false
        }
    }
}
