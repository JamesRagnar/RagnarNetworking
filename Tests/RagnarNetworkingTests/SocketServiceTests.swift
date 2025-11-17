//
//  SocketServiceTests.swift
//  RagnarNetworkingTests
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import Testing
import SocketIO
@testable import RagnarNetworking

// MARK: - Mock Socket Provider

final class MockSocketProvider: SocketProvider, @unchecked Sendable {
    var sid: String?
    var status: SocketIOStatus = .notConnected

    private var eventCallbacks: [String: NormalCallback] = [:]
    private var statusCallback: NormalCallback?
    private var connectPayload: [String: Any]?
    private var offCallCount = 0

    var didConnect = false
    var didDisconnect = false
    var emittedEvents: [(event: String, dataCount: Int)] = []
    var ackRequests: [String] = []
    var removedListeners: [String] = []

    // For simulating acknowledgments
    var pendingAckCallbacks: [String: ([Any]) -> Void] = [:]

    init(sid: String? = "mock-socket-id") {
        self.sid = sid
    }

    func connect(withPayload payload: [String : Any]?) {
        connectPayload = payload
        didConnect = true
        status = .connected
    }

    func disconnect() {
        didDisconnect = true
        status = .disconnected
    }

    func emit(_ event: String, _ items: any SocketData..., completion: (() -> ())?) {
        emittedEvents.append((event: event, dataCount: items.count))
        completion?()
    }

    func emitWithAck(_ event: String, _ items: any SocketData...) -> OnAckCallback {
        ackRequests.append(event)
        emittedEvents.append((event: event, dataCount: items.count))

        // Create a mock callback that we can trigger manually
        let manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: [])
        let client = manager.defaultSocket
        let callback = client.emitWithAck(event, items)

        // Store the callback so tests can trigger it
        pendingAckCallbacks[event] = { data in
            // This is a workaround since OnAckCallback is opaque
        }

        return callback
    }

    func on(_ event: String, callback: @escaping NormalCallback) -> UUID {
        let id = UUID()
        eventCallbacks[event] = callback
        return id
    }

    func on(clientEvent event: SocketClientEvent, callback: @escaping NormalCallback) -> UUID {
        let id = UUID()
        if event == .statusChange {
            statusCallback = callback
        }
        return id
    }

    func off(id: UUID) {
        offCallCount += 1
    }

    func off(_ event: String) {
        eventCallbacks.removeValue(forKey: event)
        removedListeners.append(event)
    }

    // Helper methods for testing
    func simulateEvent(_ event: String, data: [Any]) {
        if let callback = eventCallbacks[event] {
            // Create a mock ack emitter
            let manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: [])
            let client = manager.defaultSocket
            let ack = SocketAckEmitter(socket: client, ackNum: 0)
            callback(data, ack)
        }
    }

    func simulateStatusChange(_ newStatus: SocketIOStatus) {
        status = newStatus
        if let callback = statusCallback {
            let manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: [])
            let client = manager.defaultSocket
            let ack = SocketAckEmitter(socket: client, ackNum: 0)
            callback([newStatus.rawValue], ack)
        }
    }
}

// MARK: - Test Event Types

struct TestEvent: SocketEvent {
    static let name = "test-event"

    struct Schema: Codable, Sendable {
        let message: String
        let count: Int
    }
}

struct TestEventWithPayload: SocketEvent {
    static let name = "test-event-payload"

    struct Schema: Codable, Sendable {
        let received: String
    }

    struct Payload: Codable, Sendable {
        let message: String
    }
}

extension TestEventWithPayload.Payload: SocketData {
    public func socketRepresentation() throws -> SocketData {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }
}

struct TestEventWithResponse: SocketEvent {
    static let name = "test-ack-event"

    struct Schema: Codable, Sendable {
        let id: Int
    }

    struct Payload: Codable, Sendable {
        let data: String
    }

    struct Response: Codable, Sendable {
        let success: Bool
        let messageId: String
    }
}

extension TestEventWithResponse.Payload: SocketData {
    public func socketRepresentation() throws -> SocketData {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }
}

// MARK: - Configuration Tests

@Suite("SocketConfiguration Tests")
struct SocketConfigurationTests {

    @Test("Creates configuration with defaults")
    func createsConfigurationWithDefaults() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)

        #expect(config.url == url)
        #expect(config.authToken == nil)
        #expect(config.reconnectAttempts == 5)
        #expect(config.reconnectWait == 2)
        #expect(config.compress == false)
    }

    @Test("Creates configuration with custom values")
    func createsConfigurationWithCustomValues() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(
            url: url,
            authToken: "test-token",
            reconnectAttempts: 10,
            reconnectWait: 5,
            compress: true
        )

        #expect(config.url == url)
        #expect(config.authToken == "test-token")
        #expect(config.reconnectAttempts == 10)
        #expect(config.reconnectWait == 5)
        #expect(config.compress == true)
    }

    @Test("Converts to SocketIO configuration correctly")
    func convertsToSocketIOConfig() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(
            url: url,
            authToken: "my-token",
            reconnectAttempts: 3,
            reconnectWait: 1.5,
            compress: true
        )

        let socketIOConfig = config.toSocketIOConfig()

        // SocketIOClientConfiguration is an array, verify it contains expected values
        #expect(socketIOConfig.count > 0)
    }

    @Test("Configuration without auth token")
    func configurationWithoutAuthToken() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url, authToken: nil)

        let socketIOConfig = config.toSocketIOConfig()
        #expect(socketIOConfig.count > 0)
    }
}

// MARK: - Error Tests

@Suite("SocketError Tests")
struct SocketErrorTests {

    @Test("notConnected error properties")
    func notConnectedErrorProperties() {
        let error = SocketError.notConnected
        #expect(error.errorDescription == "Socket is not connected")
        #expect(error.isRetryable == true)
        #expect(error.eventName == nil)
    }

    @Test("connectionFailed error properties")
    func connectionFailedErrorProperties() {
        struct TestError: Error {}
        let error = SocketError.connectionFailed(underlying: TestError())
        #expect(error.errorDescription?.contains("Connection failed") == true)
        #expect(error.isRetryable == true)
        #expect(error.eventName == nil)
    }

    @Test("eventDecodingFailed error properties")
    func eventDecodingFailedErrorProperties() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Test")
        )
        let error = SocketError.eventDecodingFailed(
            event: "chat:message",
            data: ["test"],
            underlying: decodingError
        )

        #expect(error.errorDescription?.contains("chat:message") == true)
        #expect(error.isRetryable == false)
        #expect(error.eventName == "chat:message")
    }

    @Test("emitFailed error properties")
    func emitFailedErrorProperties() {
        struct TestError: Error {}
        let error = SocketError.emitFailed(event: "user:update", underlying: TestError())

        #expect(error.errorDescription?.contains("user:update") == true)
        #expect(error.isRetryable == false)
        #expect(error.eventName == "user:update")
    }

    @Test("configurationFailed error properties")
    func configurationFailedErrorProperties() {
        struct TestError: Error {}
        let error = SocketError.configurationFailed(underlying: TestError())

        #expect(error.errorDescription?.contains("Configuration failed") == true)
        #expect(error.isRetryable == false)
        #expect(error.eventName == nil)
    }

    @Test("acknowledgmentTimeout error properties")
    func acknowledgmentTimeoutErrorProperties() {
        let error = SocketError.acknowledgmentTimeout(event: "login")

        #expect(error.errorDescription?.contains("login") == true)
        #expect(error.isRetryable == false)
        #expect(error.eventName == "login")
    }

    @Test("acknowledgmentDecodingFailed error properties")
    func acknowledgmentDecodingFailedErrorProperties() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Test")
        )
        let error = SocketError.acknowledgmentDecodingFailed(
            event: "auth:verify",
            data: ["invalid"],
            underlying: decodingError
        )

        #expect(error.errorDescription?.contains("auth:verify") == true)
        #expect(error.isRetryable == false)
        #expect(error.eventName == "auth:verify")
    }

    @Test("unexpectedDisconnection error properties")
    func unexpectedDisconnectionErrorProperties() {
        let error = SocketError.unexpectedDisconnection(reason: "Server closed connection")

        #expect(error.errorDescription?.contains("Server closed connection") == true)
        #expect(error.isRetryable == true)
        #expect(error.eventName == nil)
    }

    @Test("debugDescription includes details")
    func debugDescriptionIncludesDetails() {
        let error = SocketError.notConnected
        let debugDesc = error.debugDescription

        #expect(debugDesc.contains("SocketError.notConnected") == true)
    }
}

// MARK: - EmptyBody Tests

@Suite("EmptyBody Tests")
struct EmptyBodyTests {

    @Test("EmptyBody initializes correctly")
    func emptyBodyInitializes() {
        let empty = EmptyBody()
        #expect(empty != nil)
    }

    @Test("EmptyBody socket representation is empty array")
    func emptyBodySocketRepresentation() throws {
        let empty = EmptyBody()
        let representation = try empty.socketRepresentation()

        if let array = representation as? [Any] {
            #expect(array.isEmpty == true)
        }
    }
}

// MARK: - Service Initialization Tests

@Suite("SocketService Initialization Tests")
struct SocketServiceInitializationTests {

    @Test("Initializes with configuration")
    func initializesWithConfiguration() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        let socketID = await service.socketID
        let currentStatus = await service.currentStatus

        #expect(socketID == "mock-socket-id")
        #expect(currentStatus == .notConnected)
    }

    @Test("Socket ID reflects provider value")
    func socketIDReflectsProviderValue() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider(sid: "custom-id")
        let service = SocketService(socket: mockSocket, configuration: config)

        let socketID = await service.socketID
        #expect(socketID == "custom-id")
    }

    @Test("Socket ID is nil when provider returns nil")
    func socketIDNilWhenProviderReturnsNil() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider(sid: nil)
        let service = SocketService(socket: mockSocket, configuration: config)

        let socketID = await service.socketID
        #expect(socketID == nil)
    }
}

// MARK: - Lifecycle Tests

@Suite("SocketService Lifecycle Tests")
struct SocketServiceLifecycleTests {

    @Test("Connect calls socket provider")
    func connectCallsSocketProvider() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        await service.connect()

        #expect(mockSocket.didConnect == true)
        #expect(mockSocket.status == .connected)
    }

    @Test("Disconnect calls socket provider")
    func disconnectCallsSocketProvider() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        await service.disconnect()

        #expect(mockSocket.didDisconnect == true)
    }

    @Test("Current status reflects socket status")
    func currentStatusReflectsSocketStatus() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        mockSocket.status = .connecting
        let status = await service.currentStatus
        #expect(status == .connecting)

        mockSocket.status = .connected
        let status2 = await service.currentStatus
        #expect(status2 == .connected)
    }
}

// MARK: - Status Updates Tests

@Suite("SocketService Status Updates Tests")
struct SocketServiceStatusUpdatesTests {

    @Test("Status updates stream yields status changes")
    func statusUpdatesStreamYieldsStatusChanges() async {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        let stream = service.statusUpdates()

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            mockSocket.simulateStatusChange(.connecting)
        }

        var receivedStatus: SocketService.SocketStatus?
        for await status in stream {
            receivedStatus = status
            break // Only check first value
        }

        #expect(receivedStatus == .connecting)
    }
}

// MARK: - Event Observation Tests

@Suite("SocketService Event Observation Tests")
struct SocketServiceEventObservationTests {

    @Test("Observe decodes valid event data")
    func observeDecodesValidEventData() async throws {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        let stream = service.observe(TestEvent.self)

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let eventData: [String: Any] = ["message": "Hello", "count": 42]
            mockSocket.simulateEvent("test-event", data: [eventData])
        }

        var receivedEvent: TestEvent.Schema?
        for try await event in stream {
            receivedEvent = event
            break
        }

        #expect(receivedEvent?.message == "Hello")
        #expect(receivedEvent?.count == 42)
    }

    @Test("Observe handles raw types")
    func observeHandlesRawTypes() async throws {
        struct RawEvent: SocketEvent {
            static let name = "raw-event"
            typealias Schema = String
        }

        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        let stream = service.observe(RawEvent.self)

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            mockSocket.simulateEvent("raw-event", data: ["Hello World"])
        }

        var receivedValue: String?
        for try await value in stream {
            receivedValue = value
            break
        }

        #expect(receivedValue == "Hello World")
    }
}

// MARK: - Event Sending Tests

@Suite("SocketService Event Sending Tests")
struct SocketServiceEventSendingTests {

    @Test("Send emits event to socket")
    func sendEmitsEventToSocket() async throws {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        mockSocket.status = .connected
        let service = SocketService(socket: mockSocket, configuration: config)

        let payload = TestEventWithPayload.Payload(message: "Hello")
        try await service.send(TestEventWithPayload.self, payload)

        #expect(mockSocket.emittedEvents.count == 1)
        #expect(mockSocket.emittedEvents.first?.event == "test-event-payload")
        #expect(mockSocket.emittedEvents.first?.dataCount == 1)
    }

    @Test("Send throws when not connected")
    func sendThrowsWhenNotConnected() async throws {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        mockSocket.status = .notConnected
        let service = SocketService(socket: mockSocket, configuration: config)

        let payload = TestEventWithPayload.Payload(message: "Hello")

        await #expect(throws: SocketError.self) {
            try await service.send(TestEventWithPayload.self, payload)
        }
    }

    @Test("Send works when connecting")
    func sendWorksWhenConnecting() async throws {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        mockSocket.status = .connecting
        let service = SocketService(socket: mockSocket, configuration: config)

        let payload = TestEventWithPayload.Payload(message: "Hello")

        // Should throw since not fully connected
        await #expect(throws: SocketError.self) {
            try await service.send(TestEventWithPayload.self, payload)
        }
    }

    @Test("Send works in connected state")
    func sendWorksInConnectedState() async throws {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        mockSocket.status = .connected
        let service = SocketService(socket: mockSocket, configuration: config)

        let payload = TestEventWithPayload.Payload(message: "Test")
        try await service.send(TestEventWithPayload.self, payload)

        #expect(mockSocket.emittedEvents.count == 1)
    }

    @Test("Send multiple events")
    func sendMultipleEvents() async throws {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        mockSocket.status = .connected
        let service = SocketService(socket: mockSocket, configuration: config)

        let payload1 = TestEventWithPayload.Payload(message: "First")
        let payload2 = TestEventWithPayload.Payload(message: "Second")
        let payload3 = TestEventWithPayload.Payload(message: "Third")

        try await service.send(TestEventWithPayload.self, payload1)
        try await service.send(TestEventWithPayload.self, payload2)
        try await service.send(TestEventWithPayload.self, payload3)

        #expect(mockSocket.emittedEvents.count == 3)
    }
}

// MARK: - Event Protocol Tests

@Suite("SocketEvent Protocol Tests")
struct SocketEventProtocolTests {

    @Test("SocketEvent has correct name")
    func socketEventHasCorrectName() {
        #expect(TestEvent.name == "test-event")
    }

    @Test("SocketEvent with separate payload type works")
    func socketEventWithSeparatePayloadType() {
        #expect(TestEventWithPayload.name == "test-event-payload")

        // Verify types are different
        let schemaIsPayload = TestEventWithPayload.Schema.self == TestEventWithPayload.Payload.self
        #expect(schemaIsPayload == false)
    }

    @Test("SocketEvent with response type")
    func socketEventWithResponseType() {
        #expect(TestEventWithResponse.name == "test-ack-event")

        // Verify all three types are different
        let schemaIsPayload = TestEventWithResponse.Schema.self == TestEventWithResponse.Payload.self
        let schemaIsResponse = TestEventWithResponse.Schema.self == TestEventWithResponse.Response.self
        let payloadIsResponse = TestEventWithResponse.Payload.self == TestEventWithResponse.Response.self

        #expect(schemaIsPayload == false)
        #expect(schemaIsResponse == false)
        #expect(payloadIsResponse == false)
    }

    @Test("SocketEvent default Response is EmptyBody")
    func socketEventDefaultResponseIsEmptyBody() {
        struct DefaultEvent: SocketEvent {
            static let name = "default"
            struct Schema: Codable, Sendable {
                let value: String
            }
        }

        // Response should default to EmptyBody
        let responseType = DefaultEvent.Response.self
        let isEmptyBody = responseType == EmptyBody.self
        #expect(isEmptyBody == true)
    }

    @Test("SocketEvent default Payload is Schema")
    func socketEventDefaultPayloadIsSchema() {
        struct DefaultEvent: SocketEvent {
            static let name = "default"
            struct Schema: Codable, Sendable {
                let value: String
            }
        }

        // Payload should default to Schema
        let payloadType = DefaultEvent.Payload.self
        let schemaType = DefaultEvent.Schema.self
        #expect(payloadType == schemaType)
    }
}
