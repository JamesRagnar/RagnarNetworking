import Foundation
@testable import RagnarSocketIO
import RagnarWebSocket
import Testing

enum TestTransportFailure: Error {
    case disconnected
    case sendFailed
}

actor TestWebSocketClient: WebSocketClient {
    private var queuedResults: [Result<WebSocketMessage, Error>] = []
    private var receiveContinuation: CheckedContinuation<WebSocketMessage, Error>?
    private(set) var requests: [URLRequest] = []
    private(set) var sentMessages: [WebSocketMessage] = []
    private(set) var closeCount = 0
    private var shouldFailNextSend = false

    func open(_ request: URLRequest) throws {
        requests.append(request)
    }

    func send(_ message: WebSocketMessage) async throws {
        if shouldFailNextSend {
            shouldFailNextSend = false
            throw TestTransportFailure.sendFailed
        }
        sentMessages.append(message)
    }

    func receive() async throws -> WebSocketMessage {
        if !queuedResults.isEmpty {
            return try queuedResults.removeFirst().get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveContinuation = continuation
        }
    }

    func close(code: WebSocketCloseCode, reason: Data?) {
        closeCount += 1
        receiveContinuation?.resume(throwing: TestTransportFailure.disconnected)
        receiveContinuation = nil
    }

    func inject(_ message: WebSocketMessage) {
        if let receiveContinuation {
            self.receiveContinuation = nil
            receiveContinuation.resume(returning: message)
        } else {
            queuedResults.append(.success(message))
        }
    }

    func failReceive() {
        if let receiveContinuation {
            self.receiveContinuation = nil
            receiveContinuation.resume(throwing: TestTransportFailure.disconnected)
        } else {
            queuedResults.append(.failure(TestTransportFailure.disconnected))
        }
    }

    func failNextSend() {
        shouldFailNextSend = true
    }
}

actor ManualSocketIOClock: SocketIOClock {
    struct PendingSleep {
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var nextID = 0
    private var pending: [Int: PendingSleep] = [:]

    func sleep(for duration: Duration) async throws {
        let identifier = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending[identifier] = PendingSleep(duration: duration, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(identifier) }
        }
    }

    func pendingDurations() -> [Duration] {
        pending.values.map(\.duration)
    }

    func advance(_ duration: Duration) {
        guard let match = pending.first(where: { $0.value.duration == duration }) else { return }
        pending[match.key] = nil
        match.value.continuation.resume()
    }

    private func cancel(_ identifier: Int) {
        guard let sleep = pending.removeValue(forKey: identifier) else { return }
        sleep.continuation.resume(throwing: CancellationError())
    }
}

struct FixedSocketIORandomSource: SocketIORandomSource {
    let value: Double

    func unitInterval() -> Double { value }
}

enum NumberEvent: SocketEvent {
    typealias Schema = Int
    static let name = "number"
}

/// Shares the `number` wire name with `NumberEvent` under a different schema.
enum StringNumberEvent: SocketEvent {
    typealias Schema = String
    static let name = "number"
}

enum OutgoingNumberEvent: EmittableSocketEvent {
    typealias Schema = Int
    static let name = "outgoing"
}

let socketTestEndpoint = SocketIOEndpoint.server(URL(string: "https://example.com")!)

func makeSocketClient(
    webSocket: TestWebSocketClient,
    clock: ManualSocketIOClock,
    reconnectPolicy: ReconnectPolicy = .disabled,
    namespaceTimeout: Duration = .seconds(45),
    randomValue: Double = 0.5
) -> SocketIOClient {
    SocketIOClient(
        webSocket: webSocket,
        reconnectPolicy: reconnectPolicy,
        namespaceTimeout: namespaceTimeout,
        clock: clock,
        randomSource: FixedSocketIORandomSource(value: randomValue)
    )
}

func completeHandshake(
    client: SocketIOClient,
    webSocket: TestWebSocketClient,
    openPayload: String = #"0{"sid":"session","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#
) async throws {
    try await waitUntil { await !webSocket.requests.isEmpty }
    await webSocket.inject(.text(openPayload))
    try await waitUntil { await webSocket.sentMessages.contains(.text("40")) }
    await webSocket.inject(.text("40"))
    try await waitUntil { await client.status == .connected }
}

func waitUntil(
    attempts: Int = 1_000,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<attempts {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Condition was not satisfied")
}
