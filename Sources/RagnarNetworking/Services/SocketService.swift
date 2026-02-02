//
//  SocketService.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation

public actor SocketService {

    public enum SocketStatus: Int, Sendable {

        /// The client/manager has never been connected, or the client has been reset.
        case notConnected

        /// The client/manager was once connected, but not anymore.
        case disconnected

        /// The client/manager is in the process of connecting.
        case connecting

        /// The client/manager is currently connected.
        case connected

    }

    public enum SessionState: Sendable, Equatable {
        case idle
        case starting(URL)
        case active(URL)
        case stopping(URL)

        public var url: URL? {
            switch self {
            case .idle:
                return nil
            case .starting(let url),
                 .active(let url),
                 .stopping(let url):
                return url
            }
        }

        public var isActive: Bool {
            if case .active = self {
                return true
            }
            return false
        }
    }

    public struct Status: Sendable, Equatable {
        public let session: SessionState
        public let socket: SocketStatus

        public init(session: SessionState, socket: SocketStatus) {
            self.session = session
            self.socket = socket
        }
    }

    private struct TypedEventObserver {
        let id: UUID
        let eventName: String
        let handler: (SocketEventSnapshot) -> Void
        let finish: () -> Void

        init<Event: SocketInboundEvent>(
            id: UUID,
            eventType: Event.Type,
            continuation: AsyncStream<Event.Payload>.Continuation
        ) {
            self.id = id
            self.eventName = Event.name
            self.handler = { anyEvent in
                guard let decoded = Self.decodeEvent(anyEvent, as: Event.self) else {
                    return
                }
                continuation.yield(decoded)
            }
            self.finish = {
                continuation.finish()
            }
        }

        static func decodeEvent<Event: SocketInboundEvent>(
            _ event: SocketEventSnapshot,
            as eventType: Event.Type
        ) -> Event.Payload? {
            guard let item = event.items.first else { return nil }

            let itemValue = item.asAny()

            if let item = itemValue as? Event.Payload {
                return item
            }

            if
                let jsonData = try? JSONSerialization.data(
                    withJSONObject: itemValue,
                    options: [.fragmentsAllowed]
                ),
                let decoded = try? JSONDecoder().decode(Event.Payload.self, from: jsonData)
            {
                return decoded
            }

            if event.items.count > 1 {
                let arrayValue = event.items.map { $0.asAny() }
                if
                    let jsonData = try? JSONSerialization.data(
                        withJSONObject: arrayValue,
                        options: [.fragmentsAllowed]
                    ),
                    let decoded = try? JSONDecoder().decode(Event.Payload.self, from: jsonData)
                {
                    return decoded
                }
            }

            return nil
        }
    }

    private weak var loggingService: LoggingService?

    private let configuration: SocketServiceConfiguration
    private let clientFactory: @Sendable (URL, SocketServiceConfiguration) -> any SocketClientProtocol

    private var client: (any SocketClientProtocol)?
    private var clientID: UUID?

    private var currentSocketStatus: SocketStatus = .notConnected
    private var sessionState: SessionState = .idle

    private var eventContinuations: [UUID: AsyncStream<SocketEventSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<Status>.Continuation] = [:]
    private var typedEventObservers: [String: [UUID: TypedEventObserver]] = [:]

    public func socketID() async -> String? {
        await client?.sid
    }

    public init(config: SocketServiceConfiguration = .init()) {
        self.init(
            config: config,
            clientFactory: { url, config in
                SocketIOClientAdapter(url: url, config: config)
            }
        )
    }

    init(
        config: SocketServiceConfiguration = .init(),
        clientFactory: @escaping @Sendable (URL, SocketServiceConfiguration) -> any SocketClientProtocol
    ) {
        configuration = config
        self.clientFactory = clientFactory
    }

    public func setLoggingService(_ loggingService: LoggingService?) {
        self.loggingService = loggingService
    }

    public func status() -> Status {
        Status(session: sessionState, socket: currentSocketStatus)
    }

    public func startSession(url: URL) async {
        await setSession(url: url)
    }

    public func stopSession() async {
        await setSession(url: nil)
    }

    public func setSession(url: URL?) async {
        if url == sessionState.url, client != nil {
            if currentSocketStatus != .connected {
                await client?.connect()
            }
            return
        }

        if let currentURL = sessionState.url {
            sessionState = .stopping(currentURL)
            publishStatus()
        }

        await disconnectClient()

        guard let url else {
            sessionState = .idle
            currentSocketStatus = .notConnected
            publishStatus()
            return
        }

        let newClient = clientFactory(url, configuration)
        let newClientID = UUID()
        client = newClient
        clientID = newClientID

        sessionState = .starting(url)
        currentSocketStatus = .connecting
        publishStatus()

        await configureHandlers(for: newClient, clientID: newClientID)
        await newClient.connect()
    }

    public func sendEvent<Event: SocketOutboundEvent>(
        _ eventType: Event.Type,
        _ message: Event.Payload
    ) async throws {
        guard let client, currentSocketStatus == .connected else {
            loggingService?.log(
                source: .socketService,
                level: .error,
                message: "Failed Sending Event - \(eventType.name) (not connected)"
            )
            throw SocketServiceError.notConnected
        }
        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Sending Event - \(eventType.name)"
        )

        do {
            let payload = try message.socketPayload()
            try await client.emit(eventType.name, payload)
        } catch {
            loggingService?.log(
                source: .socketService,
                level: .error,
                message: "Failed Sending Event - \(eventType.name) (\(error))"
            )
            throw error
        }
    }

    public func observeAllEvents() async -> AsyncStream<SocketEventSnapshot> {
        let (stream, continuation) = AsyncStream<SocketEventSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(configuration.eventBufferSize)
        )
        let id = UUID()
        eventContinuations[id] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id) }
        }

        return stream
    }

    public func observeStatus() async -> AsyncStream<Status> {
        let (stream, continuation) = AsyncStream<Status>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        statusContinuations[id] = continuation

        continuation.yield(status())

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }

        return stream
    }

    public func observeEvent<Event: SocketInboundEvent>(
        _ eventType: Event.Type
    ) async -> AsyncStream<Event.Payload> {
        let (stream, continuation) = AsyncStream<Event.Payload>.makeStream(
            bufferingPolicy: .bufferingNewest(configuration.eventBufferSize)
        )
        let id = UUID()

        let observer = TypedEventObserver(
            id: id,
            eventType: eventType,
            continuation: continuation
        )

        if typedEventObservers[Event.name] == nil {
            typedEventObservers[Event.name] = [:]
        }
        typedEventObservers[Event.name]?[id] = observer

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeTypedEventContinuation(id, eventName: Event.name) }
        }

        return stream
    }

    private func configureHandlers(
        for client: any SocketClientProtocol,
        clientID: UUID
    ) async {
        await client.setEventHandler { [weak self] event in
            guard let self = self else { return }
            await self.handleSocketEvent(event, clientID: clientID)
        }

        await client.setStatusHandler { [weak self] status in
            guard let self = self else { return }
            await self.handleStatusChange(status, clientID: clientID)
        }
    }

    private func handleSocketEvent(
        _ event: SocketEventSnapshot,
        clientID: UUID
    ) async {
        guard clientID == self.clientID else { return }

        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Received Event - \(event.event)"
        )
        if let description = event.firstUnsupportedDescription {
            loggingService?.log(
                source: .socketService,
                level: .debug,
                message: "Unsupported Event Payload - \(event.event) (\(description))"
            )
        }

        for continuation in eventContinuations.values {
            continuation.yield(event)
        }

        if let observers = typedEventObservers[event.event] {
            for observer in observers.values {
                observer.handler(event)
            }
        }
    }

    private func handleStatusChange(
        _ status: SocketStatus,
        clientID: UUID
    ) async {
        guard clientID == self.clientID else { return }

        currentSocketStatus = status

        if case .starting(let url) = sessionState, status == .connected {
            sessionState = .active(url)
        } else if case .stopping = sessionState, status == .disconnected {
            sessionState = .idle
            currentSocketStatus = .notConnected
        }

        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Status Change - \(status)"
        )

        publishStatus()
    }

    private func publishStatus() {
        let status = status()
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }

    private func disconnectClient() async {
        guard let client else { return }
        clientID = nil
        await client.disconnect()
        self.client = nil
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations[id]?.finish()
        eventContinuations.removeValue(forKey: id)
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations[id]?.finish()
        statusContinuations.removeValue(forKey: id)
    }

    private func removeTypedEventContinuation(_ id: UUID, eventName: String) {
        let observer = typedEventObservers[eventName]?[id]
        observer?.finish()
        typedEventObservers[eventName]?.removeValue(forKey: id)
        if typedEventObservers[eventName]?.isEmpty == true {
            typedEventObservers.removeValue(forKey: eventName)
        }
    }

}
