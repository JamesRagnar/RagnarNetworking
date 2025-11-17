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

final class MockSocketProvider: SocketProvider {
    var sid: String?
    var status: SocketIOStatus = .notConnected

    private var eventCallbacks: [String: NormalCallback] = [:]
    private var statusCallback: NormalCallback?
    private var connectPayload: [String: Any]?
    var didConnect = false
    var didDisconnect = false
    var emittedEvents: [(event: String, dataCount: Int)] = []
    var ackRequests: [String] = []

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

        // We can't easily mock OnAckCallback since it requires a SocketIOClient
        // and has internal initializers. Integration tests would use actual sockets.
        // For now, create a real manager and socket for the mock
        let manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: [])
        let client = manager.defaultSocket
        // Use the real OnAckCallback from the socket
        return client.emitWithAck(event, items)
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
        // Mock implementation
    }

    func off(_ event: String) {
        eventCallbacks.removeValue(forKey: event)
    }

    // Helper methods for testing
    func simulateEvent(_ event: String, data: [Any]) {
        if let callback = eventCallbacks[event] {
            // Note: We can't create SocketAckEmitter without a real socket
            // So event simulation is limited in unit tests
            // This would work better with integration tests
        }
    }

    func simulateStatusChange(_ newStatus: SocketIOStatus) {
        status = newStatus
        // We can't easily create SocketAckEmitter for testing due to final class
        // Status changes would be tested via integration tests
        // For unit tests, we just track the status change
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
        #expect(config.autoConnect == false)
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
            autoConnect: true,
            compress: true
        )

        #expect(config.url == url)
        #expect(config.authToken == "test-token")
        #expect(config.reconnectAttempts == 10)
        #expect(config.reconnectWait == 5)
        #expect(config.autoConnect == true)
        #expect(config.compress == true)
    }
}

// MARK: - Error Tests

@Suite("SocketError Tests")
struct SocketErrorTests {

    @Test("SocketError provides correct descriptions")
    func socketErrorDescriptions() {
        let notConnectedError = SocketError.notConnected
        #expect(notConnectedError.errorDescription == "Socket is not connected")
        #expect(notConnectedError.isRetryable == true)
        #expect(notConnectedError.eventName == nil)
    }

    @Test("Event-related errors include event name")
    func eventRelatedErrorsIncludeEventName() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Test")
        )
        let error = SocketError.eventDecodingFailed(
            event: "test-event",
            data: ["test"],
            underlying: decodingError
        )

        #expect(error.eventName == "test-event")
        #expect(error.isRetryable == false)
    }
}

// MARK: - Service Tests

@Suite("SocketService Tests")
struct SocketServiceTests {

    @Test("Initializes with configuration")
    func initializesWithConfiguration() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        #expect(service.socketID == "mock-socket-id")
        #expect(service.currentStatus == .notConnected)
    }

    @Test("Connect calls socket provider")
    func connectCallsSocketProvider() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        service.connect()

        #expect(mockSocket.didConnect == true)
    }

    @Test("Disconnect calls socket provider")
    func disconnectCallsSocketProvider() {
        let url = URL(string: "https://example.com")!
        let config = SocketConfiguration(url: url)
        let mockSocket = MockSocketProvider()
        let service = SocketService(socket: mockSocket, configuration: config)

        service.disconnect()

        #expect(mockSocket.didDisconnect == true)
    }

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
}
