import Foundation
import RagnarSocketIO
import Testing

let socketIOIntegrationEnabled = ProcessInfo.processInfo.environment["RUN_SOCKETIO_INTEGRATION_TESTS"] == "1"

func withIntegrationServer<Result: Sendable>(
    path: String = "/socket.io/",
    operation: (IntegrationServer) async throws -> Result
) async throws -> Result {
    let server = try await IntegrationServer.start(path: path)
    do {
        let result = try await operation(server)
        await server.stop()
        return result
    } catch {
        await server.stop()
        let diagnostics = await server.diagnostics()
        if !diagnostics.isEmpty {
            Issue.record("Reference server diagnostics:\n\(diagnostics)")
        }
        throw error
    }
}

func makeIntegrationClient() throws -> SocketIOClient {
    SocketIOClient(
        reconnectPolicy: try ReconnectPolicy(
            initialDelay: .milliseconds(20),
            maximumDelay: .milliseconds(100),
            multiplier: 2,
            jitter: 0,
            maximumAttempts: 5
        ),
        namespaceTimeout: .seconds(2)
    )
}

func waitForStatus(
    _ expected: SocketConnectionStatus,
    from client: SocketIOClient,
    timeout: Duration = .seconds(5)
) async throws {
    let stream = await client.statusUpdates()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for await status in stream where status == expected {
                return
            }
            throw IntegrationTestError.statusStreamEnded
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw IntegrationTestError.timeout
        }
        _ = try await group.next()
        group.cancelAll()
    }
}

func waitForStatus(
    _ expected: SocketConnectionStatus,
    in stream: AsyncStream<SocketConnectionStatus>,
    timeout: Duration = .seconds(5)
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for await status in stream where status == expected {
                return
            }
            throw IntegrationTestError.statusStreamEnded
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw IntegrationTestError.timeout
        }
        _ = try await group.next()
        group.cancelAll()
    }
}

func nextValue<Event: SocketEvent>(
    from stream: SocketEventStream<Event>,
    timeout: Duration = .seconds(5)
) async throws -> Event.Schema {
    try await withThrowingTaskGroup(of: Event.Schema.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let value = try await iterator.next() else {
                throw IntegrationTestError.eventStreamEnded
            }
            return value
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw IntegrationTestError.timeout
        }
        guard let value = try await group.next() else {
            throw IntegrationTestError.eventStreamEnded
        }
        group.cancelAll()
        return value
    }
}

enum IntegrationTestError: Error {
    case timeout
    case statusStreamEnded
    case eventStreamEnded
}
