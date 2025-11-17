//
//  SocketService.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO
import Synchronization

/// Actor-based service for managing socket.io connections with type-safe event handling.
///
/// `SocketService` provides a modern async/await API for socket.io communication, with
/// automatic concurrency safety through Swift's actor model. Use this service to connect
/// to socket.io servers, emit and observe events, and handle acknowledgments in a type-safe manner.
///
/// Example:
/// ```swift
/// // Initialize with configuration
/// let config = SocketConfiguration(
///     url: URL(string: "https://api.example.com")!,
///     authToken: "user-token"
/// )
/// let socket = SocketService(configuration: config)
///
/// // Connect to server
/// await socket.connect()
///
/// // Observe status changes
/// for await status in socket.statusUpdates() {
///     print("Status: \(status)")
/// }
///
/// // Observe events
/// for try await message in socket.observe(ChatMessageEvent.self) {
///     print("Message: \(message.text)")
/// }
///
/// // Send events
/// try await socket.send(ChatMessageEvent.self, payload)
///
/// // Send with acknowledgment
/// let response = try await socket.sendWithAck(LoginEvent.self, credentials)
/// ```
public actor SocketService {

    // MARK: - Types

    /// Socket connection status
    public enum SocketStatus: Int, Sendable {

        /// Not yet connected or connection has been reset
        case notConnected

        /// Previously connected but currently disconnected
        case disconnected

        /// Connection in progress
        case connecting

        /// Currently connected to the server
        case connected
    }

    // MARK: - Properties

    /// Optional logging service for debugging socket operations
    public weak nonisolated(unsafe) var loggingService: LoggingService?

    private nonisolated(unsafe) let socket: SocketProvider
    private let configuration: SocketConfiguration

    private var statusContinuation: AsyncStream<SocketStatus>.Continuation?
    private var eventListenerIDs: [String: UUID] = [:]

    /// The socket's unique session identifier, if connected
    public var socketID: String? {
        socket.sid
    }

    /// Current connection status
    public var currentStatus: SocketStatus {
        SocketStatus(rawValue: socket.status.rawValue) ?? .notConnected
    }

    // MARK: - Initialization

    /// Creates a new socket service with the specified configuration.
    ///
    /// The socket will not automatically connect. Call `connect()` when ready.
    ///
    /// - Parameter configuration: Socket connection settings
    public init(configuration: SocketConfiguration) {
        self.configuration = configuration

        let manager = SocketManager(
            socketURL: configuration.url,
            config: configuration.toSocketIOConfig()
        )
        self.socket = manager.defaultSocket

        setupEventHandlers()
    }

    internal init(socket: SocketProvider, configuration: SocketConfiguration) {
        self.socket = socket
        self.configuration = configuration
        setupEventHandlers()
    }

    // MARK: - Lifecycle

    /// Initiates connection to the socket.io server.
    ///
    /// This method returns immediately. Monitor connection status using `statusUpdates()`
    /// or check `currentStatus` to confirm the connection is established.
    public func connect() {
        loggingService?.log(
            source: .socketService,
            level: .debug,
            message: "Connecting socket"
        )
        socket.connect(withPayload: nil)
    }

    /// Disconnects from the socket.io server and cleans up event listeners.
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

    /// Returns an async stream of socket connection status changes.
    ///
    /// The stream yields new status values whenever the socket connection state changes.
    /// This stream never completes and can be iterated indefinitely.
    ///
    /// Example:
    /// ```swift
    /// for await status in socket.statusUpdates() {
    ///     switch status {
    ///     case .connected:
    ///         print("Socket connected")
    ///     case .disconnected:
    ///         print("Socket disconnected")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: An async stream that yields status changes
    public nonisolated func statusUpdates() -> AsyncStream<SocketStatus> {
        AsyncStream { continuation in
            let listenerID = socket.on(clientEvent: .statusChange) { [weak self] (status, _) in
                guard
                    let statusInt = status.last as? Int,
                    let socketStatus = SocketStatus(rawValue: statusInt)
                else { return }

                self?.loggingService?.log(
                    source: .socketService,
                    level: .debug,
                    message: "Status Change - \(socketStatus)"
                )

                continuation.yield(socketStatus)
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.cleanupStatusListener(listenerID)
                }
            }

            Task {
                await self.storeStatusContinuation(continuation)
            }
        }
    }

    private func storeStatusContinuation(_ continuation: AsyncStream<SocketStatus>.Continuation) {
        self.statusContinuation = continuation
    }

    private func cleanupStatusListener(_ listenerID: UUID) {
        socket.off(id: listenerID)
        statusContinuation = nil
    }

    // MARK: - Event Observation

    /// Returns an async stream of events emitted by the server.
    ///
    /// The stream yields decoded event data whenever the server emits the specified event.
    /// The stream finishes with an error if event decoding fails.
    ///
    /// Example:
    /// ```swift
    /// for try await message in socket.observe(ChatMessageEvent.self) {
    ///     print("User \(message.userId): \(message.text)")
    /// }
    /// ```
    ///
    /// - Parameter eventType: The type of event to observe
    /// - Returns: An async throwing stream that yields decoded event data
    public nonisolated func observe<Event: SocketEvent>(
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
            Task {
                await self.storeEventListener(Event.name, listenerID: listenerID)
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.cleanupEventListener(Event.name, listenerID: listenerID)
                }
            }
        }
    }

    private func storeEventListener(_ eventName: String, listenerID: UUID) {
        eventListenerIDs[eventName] = listenerID
    }

    private func cleanupEventListener(_ eventName: String, listenerID: UUID) {
        socket.off(id: listenerID)
        eventListenerIDs.removeValue(forKey: eventName)
    }

    // MARK: - Sending Events

    /// Emits an event to the server without waiting for acknowledgment.
    ///
    /// This is a fire-and-forget operation. The method returns immediately after
    /// emitting the event, without waiting for the server to acknowledge receipt.
    ///
    /// Example:
    /// ```swift
    /// let message = ChatMessageEvent.Payload(text: "Hello!")
    /// try await socket.send(ChatMessageEvent.self, message)
    /// ```
    ///
    /// - Parameters:
    ///   - eventType: The type of event to send
    ///   - payload: The event data to send
    /// - Throws: `SocketError.notConnected` if the socket is not connected
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

    /// Emits an event to the server and waits for an acknowledgment response.
    ///
    /// This method suspends until the server acknowledges the event and sends a response,
    /// or until the timeout expires. The response data is automatically decoded into the
    /// event's `Response` type.
    ///
    /// Example:
    /// ```swift
    /// let credentials = LoginEvent.Payload(username: "user", password: "pass")
    /// let response = try await socket.sendWithAck(LoginEvent.self, credentials, timeout: 5.0)
    /// print("Login successful: \(response.token)")
    /// ```
    ///
    /// - Parameters:
    ///   - eventType: The type of event to send
    ///   - payload: The event data to send
    ///   - timeout: Maximum time to wait for acknowledgment in seconds (default: 10)
    /// - Returns: The decoded acknowledgment response from the server
    /// - Throws: `SocketError.notConnected` if not connected, `SocketError.acknowledgmentTimeout`
    ///           if the server doesn't respond within the timeout, or decoding errors
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
            // Set up acknowledgment callback
            let ackCallback = socket.emitWithAck(Event.name, payload)

            // Wait for acknowledgment with timeout
            // Note: SocketIO guarantees this callback is called exactly once
            ackCallback.timingOut(after: timeout) { [weak self] data in
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

    private nonisolated func setupEventHandlers() {
        // Global event handler for logging
        _ = socket.on("") { [weak self] (data, ack) in
            self?.loggingService?.log(
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

    private nonisolated func decodeEvent<Event: SocketEvent>(
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

    private nonisolated func decodeEvent<Event: SocketEvent>(
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
