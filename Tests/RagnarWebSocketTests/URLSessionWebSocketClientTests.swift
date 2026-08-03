import Foundation
@testable import RagnarWebSocket
import Testing

private final class MockWebSocketTask: URLSessionWebSocketTaskProtocol, @unchecked Sendable {
    private let stream: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>
    private let continuation: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>.Continuation
    private var iterator: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>.AsyncIterator

    nonisolated(unsafe) private(set) var resumeCount = 0
    nonisolated(unsafe) private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    nonisolated(unsafe) private(set) var close: (URLSessionWebSocketTask.CloseCode, Data?)?

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream()
        iterator = stream.makeAsyncIterator()
    }

    func resume() {
        resumeCount += 1
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        close = (closeCode, reason)
        continuation.finish(throwing: CancellationError())
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard let message = try await iterator.next() else {
            throw URLError(.networkConnectionLost)
        }
        return message
    }

    func yield(_ message: URLSessionWebSocketTask.Message) {
        continuation.yield(message)
    }

    func fail(_ error: any Error) {
        continuation.finish(throwing: error)
    }
}

private let request = URLRequest(url: URL(string: "wss://example.com/socket")!)

@Suite("URLSession WebSocket Client")
struct URLSessionWebSocketClientTests {
    @Test("Open validates the request and resumes one task")
    func openValidation() async throws {
        let task = MockWebSocketTask()
        let client = URLSessionWebSocketClient { _ in task }

        await #expect(throws: WebSocketError.invalidRequest) {
            try await client.open(URLRequest(url: URL(string: "https://example.com")!))
        }
        try await client.open(request)

        #expect(task.resumeCount == 1)
        await #expect(throws: WebSocketError.connectionAlreadyActive) {
            try await client.open(request)
        }
    }

    @Test("Send maps text and binary messages")
    func sendMessages() async throws {
        let task = MockWebSocketTask()
        let client = URLSessionWebSocketClient { _ in task }
        try await client.open(request)

        try await client.send(.text("hello"))
        try await client.send(.binary(Data([1, 2, 3])))

        #expect(task.sentMessages.count == 2)
        guard case .string("hello") = task.sentMessages[0] else {
            Issue.record("Expected a text message")
            return
        }
        guard case .data(Data([1, 2, 3])) = task.sentMessages[1] else {
            Issue.record("Expected a binary message")
            return
        }
    }

    @Test("Receive maps text and binary messages")
    func receiveMessages() async throws {
        let task = MockWebSocketTask()
        let client = URLSessionWebSocketClient { _ in task }
        try await client.open(request)

        task.yield(.string("hello"))
        #expect(try await client.receive() == .text("hello"))
        task.yield(.data(Data([1, 2, 3])))
        #expect(try await client.receive() == .binary(Data([1, 2, 3])))
    }

    @Test("Operations require an active connection")
    func inactiveOperations() async {
        let client = URLSessionWebSocketClient { _ in MockWebSocketTask() }

        await #expect(throws: WebSocketError.noActiveConnection) {
            try await client.send(.text("hello"))
        }
        await #expect(throws: WebSocketError.noActiveConnection) {
            try await client.receive()
        }
    }

    @Test("Only one receive may be active")
    func concurrentReceive() async throws {
        let task = MockWebSocketTask()
        let client = URLSessionWebSocketClient { _ in task }
        try await client.open(request)

        let firstReceive = Task { try await client.receive() }
        await Task.yield()
        await #expect(throws: WebSocketError.concurrentReceive) {
            try await client.receive()
        }
        task.yield(.string("first"))
        #expect(try await firstReceive.value == .text("first"))
    }

    @Test("Close maps its code and reason and is idempotent")
    func close() async throws {
        let task = MockWebSocketTask()
        let client = URLSessionWebSocketClient { _ in task }
        let reason = Data("done".utf8)
        try await client.open(request)

        await client.close(code: .goingAway, reason: reason)
        await client.close(code: .protocolError, reason: nil)

        #expect(task.close?.0 == .goingAway)
        #expect(task.close?.1 == reason)
    }

    @Test("A suspended receive cannot cross connection generations")
    func staleReceive() async throws {
        let firstTask = MockWebSocketTask()
        let secondTask = MockWebSocketTask()
        nonisolated(unsafe) var tasks = [firstTask, secondTask]
        let client = URLSessionWebSocketClient { _ in tasks.removeFirst() }
        try await client.open(request)

        let receive = Task { try await client.receive() }
        await Task.yield()
        await client.close(code: .goingAway, reason: nil)
        try await client.open(request)

        await #expect(throws: WebSocketError.connectionReplacedOrClosed) {
            try await receive.value
        }
    }

    @Test("Underlying failures preserve a Sendable snapshot")
    func transportFailure() async throws {
        let task = MockWebSocketTask()
        let client = URLSessionWebSocketClient { _ in task }
        try await client.open(request)
        task.fail(URLError(.timedOut))

        do {
            _ = try await client.receive()
            Issue.record("Expected receive to fail")
        } catch let WebSocketError.transport(snapshot) {
            #expect(!snapshot.typeName.isEmpty)
            #expect(!snapshot.description.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
