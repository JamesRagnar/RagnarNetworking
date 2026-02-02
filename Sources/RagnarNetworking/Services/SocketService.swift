//
//  SocketService.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

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

    private struct TypedEventObserver {
        let id: UUID
        let eventName: String
        let handler: (SocketEventSnapshot) -> Void

        init<Event: SocketEvent>(
            id: UUID,
            eventType: Event.Type,
            continuation: AsyncStream<Event.Schema>.Continuation
        ) {
            self.id = id
            self.eventName = Event.name
            self.handler = { anyEvent in
                guard let decoded = Self.decodeEvent(anyEvent, as: Event.self) else {
                    return
                }
                continuation.yield(decoded)
            }
        }

        static func decodeEvent<Event: SocketEvent>(
            _ event: SocketEventSnapshot,
            as eventType: Event.Type
        ) -> Event.Schema? {
            guard let item = event.items.first else { return nil }

            let itemValue = item.asAny()

            if let item = itemValue as? Event.Schema {
                return item
            }

            if
                let jsonData = try? JSONSerialization.data(
                    withJSONObject: itemValue,
                    options: [.fragmentsAllowed]
                ),
                let decoded = try? JSONDecoder().decode(Event.Schema.self, from: jsonData)
            {
                return decoded
            }

            return nil
        }
    }

    public weak var loggingService: LoggingService?

    private let client: SocketClientProtocol
    private var currentStatus: SocketStatus = .notConnected
    private var eventContinuations: [UUID: AsyncStream<SocketEventSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<SocketStatus>.Continuation] = [:]
    private var typedEventObservers: [String: [UUID: TypedEventObserver]] = [:]
    private var handlersConfigured = false

    public func socketID() async -> String? {
        await client.sid
    }

    public init(url: URL, config: SocketServiceConfiguration = .init()) {
        client = SocketIOClientAdapter(url: url, config: config)
    }

    init(client: SocketClientProtocol) {
        self.client = client
    }

    public func status() -> SocketStatus {
        currentStatus
    }

    public func connect() async {
        await ensureHandlersConfigured()
        await client.connect()
    }

    public func disconnect() async {
        await client.disconnect()
        if currentStatus != .disconnected {
            handleStatusChange(.disconnected)
        }
        cleanupAllContinuations()
    }

    public func sendEvent<Event: SendableSocketEvent>(
        _ eventType: Event.Type,
        _ message: Event.Schema
    ) async {
        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Sending Event - \(eventType.name)"
        )

        await client.emit(eventType.name, message)
    }

    public func observeAllEvents() async -> AsyncStream<SocketEventSnapshot> {
        await ensureHandlersConfigured()
        let (stream, continuation) = AsyncStream<SocketEventSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(100)
        )
        let id = UUID()
        eventContinuations[id] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id) }
        }

        return stream
    }

    public func observeStatus() async -> AsyncStream<SocketStatus> {
        await ensureHandlersConfigured()
        let (stream, continuation) = AsyncStream<SocketStatus>.makeStream()
        let id = UUID()
        statusContinuations[id] = continuation

        continuation.yield(currentStatus)

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }

        return stream
    }

    public func observeEvent<Event: SocketEvent>(
        _ eventType: Event.Type
    ) async -> AsyncStream<Event.Schema> {
        await ensureHandlersConfigured()
        let (stream, continuation) = AsyncStream<Event.Schema>.makeStream()
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

    private func ensureHandlersConfigured() async {
        guard !handlersConfigured else { return }
        handlersConfigured = true

        await client.setEventHandler { [weak self] event in
            guard let self = self else { return }
            Task { await self.handleSocketEvent(event) }
        }

        await client.setStatusHandler { [weak self] status in
            guard let self = self else { return }

            Task { await self.handleStatusChange(status) }
        }
    }

    private func handleSocketEvent(_ event: SocketEventSnapshot) {
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

    private func handleStatusChange(_ status: SocketStatus) {
        currentStatus = status

        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Status Change - \(status)"
        )

        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
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
        typedEventObservers[eventName]?.removeValue(forKey: id)
        if typedEventObservers[eventName]?.isEmpty == true {
            typedEventObservers.removeValue(forKey: eventName)
        }
    }

    private func cleanupAllContinuations() {
        for continuation in eventContinuations.values {
            continuation.finish()
        }
        eventContinuations.removeAll()

        for continuation in statusContinuations.values {
            continuation.finish()
        }
        statusContinuations.removeAll()

        typedEventObservers.removeAll()
    }

}
