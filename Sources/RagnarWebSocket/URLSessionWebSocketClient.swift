import Foundation

protocol URLSessionWebSocketTaskProtocol: AnyObject, Sendable {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
}

extension URLSessionWebSocketTask: URLSessionWebSocketTaskProtocol {}

/// A `WebSocketClient` backed by one `URLSessionWebSocketTask` at a time.
public actor URLSessionWebSocketClient: WebSocketClient {
    private let taskFactory: @Sendable (URLRequest) -> any URLSessionWebSocketTaskProtocol
    private var task: (any URLSessionWebSocketTaskProtocol)?
    private var generation: UInt64 = 0
    private var isReceiving = false

    /// Creates a client that obtains WebSocket tasks from `session`.
    public init(session: URLSession = .shared) {
        taskFactory = { request in
            session.webSocketTask(with: request)
        }
    }

    init(taskFactory: @escaping @Sendable (URLRequest) -> any URLSessionWebSocketTaskProtocol) {
        self.taskFactory = taskFactory
    }

    /// Validates and resumes a new WebSocket task.
    ///
    /// The request must contain a `ws` or `wss` URL with a host. The method returns after resuming the task.
    /// It does not wait for the HTTP upgrade response.
    public func open(_ request: URLRequest) throws {
        guard Self.isValid(request) else {
            throw WebSocketError.invalidRequest
        }
        guard task == nil else {
            throw WebSocketError.connectionAlreadyActive
        }

        generation &+= 1
        let newTask = taskFactory(request)
        task = newTask
        newTask.resume()
    }

    /// Sends one message on the active task.
    ///
    /// If the task closes while this operation is suspended, the method throws
    /// `WebSocketError.connectionReplacedOrClosed`.
    public func send(_ message: WebSocketMessage) async throws {
        guard let task else {
            throw WebSocketError.noActiveConnection
        }

        let operationGeneration = generation
        do {
            try await task.send(message.foundationValue)
        } catch {
            guard operationGeneration == generation else {
                throw WebSocketError.connectionReplacedOrClosed
            }
            throw WebSocketError.transport(WebSocketErrorSnapshot(error))
        }

        guard operationGeneration == generation else {
            throw WebSocketError.connectionReplacedOrClosed
        }
    }

    /// Receives one message from the active task.
    ///
    /// Only one receive operation may be active. If the task closes while this operation is suspended, the method
    /// throws `WebSocketError.connectionReplacedOrClosed`.
    public func receive() async throws -> WebSocketMessage {
        guard let task else {
            throw WebSocketError.noActiveConnection
        }
        guard !isReceiving else {
            throw WebSocketError.concurrentReceive
        }

        let operationGeneration = generation
        isReceiving = true
        defer { isReceiving = false }

        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            guard operationGeneration == generation else {
                throw WebSocketError.connectionReplacedOrClosed
            }
            throw WebSocketError.transport(WebSocketErrorSnapshot(error))
        }

        guard operationGeneration == generation else {
            throw WebSocketError.connectionReplacedOrClosed
        }
        return WebSocketMessage(message)
    }

    /// Clears and closes the active task with the supplied close frame.
    ///
    /// Calling this method repeatedly has no effect after the first close.
    public func close(code: WebSocketCloseCode = .normalClosure, reason: Data? = nil) {
        guard let task else { return }

        generation &+= 1
        self.task = nil
        task.cancel(with: code.foundationValue, reason: reason)
    }

    private static func isValid(_ request: URLRequest) -> Bool {
        guard
            let url = request.url,
            let scheme = url.scheme?.lowercased(),
            scheme == "ws" || scheme == "wss",
            let host = url.host,
            !host.isEmpty
        else {
            return false
        }
        return true
    }
}

private extension WebSocketMessage {
    var foundationValue: URLSessionWebSocketTask.Message {
        switch self {
        case .text(let value):
            .string(value)

        case .binary(let value):
            .data(value)
        }
    }

    init(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let value):
            self = .text(value)

        case .data(let value):
            self = .binary(value)

        @unknown default:
            preconditionFailure("Unsupported URLSessionWebSocketTask message")
        }
    }
}
