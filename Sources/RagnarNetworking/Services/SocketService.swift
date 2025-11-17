//
//  SocketService.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Modern async/await-based socket service
public final class SocketService: @unchecked Sendable {

    // MARK: - Types

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

    // MARK: - Properties

    public weak var loggingService: LoggingService?

    private let socket: SocketProvider
    private let configuration: SocketConfiguration

    // Stream management
    private var statusContinuation: AsyncStream<SocketStatus>.Continuation?
    private var eventListenerIDs: [String: UUID] = [:]

    /// The socket's unique identifier
    public var socketID: String? {
        socket.sid
    }

    /// Current connection status
    public var currentStatus: SocketStatus {
        SocketStatus(rawValue: socket.status.rawValue) ?? .notConnected
    }

    // MARK: - Initialization

    /// Initialize with a configuration
    public init(configuration: SocketConfiguration) {
        self.configuration = configuration

        // Create socket manager and get default socket
        let manager = SocketManager(
            socketURL: configuration.url,
            config: configuration.toSocketIOConfig()
        )
        self.socket = manager.defaultSocket

        setupEventHandlers()

        // Auto-connect if configured
        if configuration.autoConnect {
            connect()
        }
    }

    /// Initialize with a custom socket provider (for testing)
    internal init(socket: SocketProvider, configuration: SocketConfiguration) {
        self.socket = socket
        self.configuration = configuration
        setupEventHandlers()
    }

    // MARK: - Lifecycle

    /// Connect the socket
    public func connect() {
        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Connecting socket"
        )
        socket.connect(withPayload: nil)
    }

    /// Disconnect the socket
    public func disconnect() {
        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Disconnecting socket"
        )
        socket.disconnect()
        cleanupEventListeners()
    }

    // MARK: - Status Updates

    /// Observe socket status changes
    public func statusUpdates() -> AsyncStream<SocketStatus> {
        AsyncStream { continuation in
            // Store continuation for cleanup
            self.statusContinuation = continuation

            // Set up status listener
            let listenerID = socket.on(clientEvent: .statusChange) { [weak self] (status, _) in
                guard
                    let self = self,
                    let statusInt = status.last as? Int,
                    let socketStatus = SocketStatus(rawValue: statusInt)
                else { return }

                self.loggingService?.log(
                    source: .socketService,
                    level: .debug,
                    message: "Status Change - \(socketStatus)"
                )
                continuation.yield(socketStatus)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.socket.off(id: listenerID)
                self.statusContinuation = nil
            }
        }
    }

    // MARK: - Event Observation

    /// Observe a specific socket event
    public func observe<Event: SocketEvent>(
        _ eventType: Event.Type
    ) -> AsyncThrowingStream<Event.Schema, Error> {
        AsyncThrowingStream { continuation in
            let listenerID = socket.on(Event.name) { [weak self] (data, _) in
                guard let self = self else { return }

                self.loggingService?.log(
                    source: .socketService,
                    level: .debug,
                    message: "Received Event - \(Event.name)"
                )

                do {
                    let decoded = try self.decodeEvent(Event.self, from: data)
                    continuation.yield(decoded)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Store listener ID for cleanup
            self.eventListenerIDs[Event.name] = listenerID

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.socket.off(id: listenerID)
                self.eventListenerIDs.removeValue(forKey: Event.name)
            }
        }
    }

    // MARK: - Sending Events

    /// Send an event without expecting acknowledgment
    public func send<Event: SocketEvent>(
        _ eventType: Event.Type,
        _ payload: Event.Payload
    ) async throws where Event.Payload: SocketData {
        guard currentStatus == .connected else {
            throw SocketError.notConnected
        }

        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Sending Event - \(Event.name)"
        )

        socket.emit(Event.name, payload, completion: nil)
    }

    /// Send an event and wait for acknowledgment
    public func sendWithAck<Event: SocketEvent>(
        _ eventType: Event.Type,
        _ payload: Event.Payload,
        timeout: TimeInterval = 10.0
    ) async throws -> Event.Response where Event.Payload: SocketData {
        guard currentStatus == .connected else {
            throw SocketError.notConnected
        }

        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Sending Event with Ack - \(Event.name)"
        )

        return try await withCheckedThrowingContinuation { continuation in
            var didComplete = false

            // Set up acknowledgment callback
            let ackCallback = socket.emitWithAck(Event.name, payload)

            // Wait for acknowledgment with timeout
            ackCallback.timingOut(after: timeout) { [weak self] data in
                guard !didComplete else { return }
                didComplete = true

                guard let self = self else { return }

                // Check if timeout occurred
                if data.isEmpty || (data.first as? String) == "NO ACK" {
                    continuation.resume(throwing: SocketError.acknowledgmentTimeout(event: Event.name))
                    return
                }

                do {
                    let decoded = try self.decodeEvent(Event.self, responseFrom: data)
                    continuation.resume(returning: decoded)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func setupEventHandlers() {
        // Global event handler for logging
        _ = socket.on("") { [weak self] (data, ack) in
            guard let self = self else { return }
            self.loggingService?.log(
                source: .socketService,
                level: .debug,
                message: "Socket event received"
            )
        }
    }
    
    private func cleanupEventListeners() {
        for (_, listenerID) in eventListenerIDs {
            socket.off(id: listenerID)
        }
        eventListenerIDs.removeAll()
        statusContinuation?.finish()
        statusContinuation = nil
    }

    private func decodeEvent<Event: SocketEvent>(
        _ eventType: Event.Type,
        from data: [Any]
    ) throws -> Event.Schema {
        guard let item = data.first else {
            throw SocketError.eventDecodingFailed(
                event: Event.name,
                data: data,
                underlying: DecodingError.valueNotFound(
                    Event.Schema.self,
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "No data in event"
                    )
                )
            )
        }

        // Handle raw types
        if let item = item as? Event.Schema {
            return item
        }

        // Handle decodable types
        guard let dict = item as? [String: Any] else {
            throw SocketError.eventDecodingFailed(
                event: Event.name,
                data: data,
                underlying: DecodingError.typeMismatch(
                    [String: Any].self,
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Expected dictionary, got \(type(of: item))"
                    )
                )
            )
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            let decoded = try JSONDecoder().decode(Event.Schema.self, from: jsonData)
            return decoded
        } catch {
            throw SocketError.eventDecodingFailed(
                event: Event.name,
                data: data,
                underlying: error
            )
        }
    }

    private func decodeEvent<Event: SocketEvent>(
        _ eventType: Event.Type,
        responseFrom data: [Any]
    ) throws -> Event.Response {
        // Handle empty response (EmptyBody)
        if Event.Response.self == EmptyBody.self {
            return EmptyBody() as! Event.Response
        }

        guard let item = data.first else {
            throw SocketError.acknowledgmentDecodingFailed(
                event: Event.name,
                data: data,
                underlying: DecodingError.valueNotFound(
                    Event.Response.self,
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "No data in acknowledgment"
                    )
                )
            )
        }

        // Handle raw types
        if let item = item as? Event.Response {
            return item
        }

        // Handle decodable types
        guard let dict = item as? [String: Any] else {
            throw SocketError.acknowledgmentDecodingFailed(
                event: Event.name,
                data: data,
                underlying: DecodingError.typeMismatch(
                    [String: Any].self,
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Expected dictionary, got \(type(of: item))"
                    )
                )
            )
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            let decoded = try JSONDecoder().decode(Event.Response.self, from: jsonData)
            return decoded
        } catch {
            throw SocketError.acknowledgmentDecodingFailed(
                event: Event.name,
                data: data,
                underlying: error
            )
        }
    }
}
