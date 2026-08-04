import Foundation
import OSLog
import RagnarWebSocket

enum LifecycleFailure: Error, Sendable {
    case reconnectable(SocketConnectionFailure)
    case terminal(SocketConnectionFailure)
    case serverDisconnect
}

enum ConnectionLoopAction {
    case retry(Int)
    case stop
}

extension SocketIOClient {
    func runConnectionLoop(generation connectionGeneration: UInt64, request: URLRequest) async {
        var reconnectAttempt = 0
        defer { finishConnectionLoop(generation: connectionGeneration) }

        while isCurrent(connectionGeneration) {
            guard await prepareReconnect(attempt: reconnectAttempt, generation: connectionGeneration) else { break }

            do {
                try await runConnection(generation: connectionGeneration, request: request)
                break
            } catch {
                switch await handleConnectionFailure(
                    error,
                    reconnectAttempt: reconnectAttempt,
                    generation: connectionGeneration
                ) {
                case .retry(let nextAttempt):
                    reconnectAttempt = nextAttempt

                case .stop:
                    return
                }
            }
        }
    }

    func prepareReconnect(attempt: Int, generation connectionGeneration: UInt64) async -> Bool {
        guard attempt > 0 else { return true }
        guard canReconnect(attempt: attempt) else {
            let failure = SocketConnectionFailure.reconnectExhausted(attempts: attempt - 1)
            logTerminalFailure(failure)
            setStatus(.failed(failure))
            return false
        }
        setStatus(.reconnecting(attempt: attempt))
        let delay = reconnectDelay(attempt: attempt)
        Logger.socketIO.debug(
            """
            Reconnect attempt \(attempt, privacy: .public) \
            in \(delay.loggableSeconds, format: .fixed(precision: 3), privacy: .public)s
            """
        )
        do {
            try await clock.sleep(for: delay)
        } catch {
            return false
        }
        return isCurrent(connectionGeneration)
    }

    func handleConnectionFailure(
        _ error: any Error,
        reconnectAttempt: Int,
        generation connectionGeneration: UInt64
    ) async -> ConnectionLoopAction {
        guard isCurrent(connectionGeneration) else { return .stop }
        await closeTransport()

        switch error {
        case LifecycleFailure.reconnectable(let failure):
            guard reconnectPolicy.enabled else {
                logTerminalFailure(failure)
                setStatus(.failed(failure))
                return .stop
            }
            logRetryableFailure(failure)
            return .retry(status == .connected ? 1 : reconnectAttempt + 1)

        case LifecycleFailure.terminal(let failure):
            logTerminalFailure(failure)
            setStatus(.failed(failure))
            return .stop

        case LifecycleFailure.serverDisconnect:
            Logger.socketIO.debug("Server disconnected the namespace")
            setStatus(.disconnected)
            return .stop

        default:
            let failure = transportFailure(error)
            guard reconnectPolicy.enabled else {
                logTerminalFailure(failure)
                setStatus(.failed(failure))
                return .stop
            }
            logRetryableFailure(failure)
            return .retry(reconnectAttempt + 1)
        }
    }

    func runConnection(generation connectionGeneration: UInt64, request: URLRequest) async throws {
        if let pendingCloseTask {
            await pendingCloseTask.value
            guard isCurrent(connectionGeneration) else { throw CancellationError() }
            self.pendingCloseTask = nil
        }
        await webSocket.close(code: .goingAway, reason: nil)
        guard isCurrent(connectionGeneration) else { throw CancellationError() }

        do {
            try await webSocket.open(request)
        } catch {
            throw LifecycleFailure.reconnectable(transportFailure(error))
        }

        // A connection becomes usable in two protocol stages: Engine.IO OPEN establishes transport parameters, then the
        // default Socket.IO namespace CONNECT establishes event semantics.
        let firstMessage = try await receive(generation: connectionGeneration)
        guard case .text(let text) = firstMessage else {
            throw LifecycleFailure.terminal(.unsupportedCapability("binary Engine.IO transport"))
        }

        // A fresh handshake can clear a junk or out-of-order first frame, so these retry under the reconnect policy.
        // The capability mismatches around them cannot be cleared by retrying and stay terminal.
        let firstPacket: EngineIOPacket
        do {
            firstPacket = try EngineIOCodec.decode(text)
        } catch {
            throw LifecycleFailure.reconnectable(protocolFailure(error))
        }
        guard case .open(let openPayload) = firstPacket else {
            throw LifecycleFailure.reconnectable(.protocolViolation("Engine.IO OPEN was not the first packet"))
        }
        guard openPayload.upgrades.isEmpty else {
            throw LifecycleFailure.terminal(.unsupportedCapability("Engine.IO transport upgrade"))
        }

        Logger.socketIO.debug(
            """
            Engine.IO OPEN: pingInterval \
            \(openPayload.pingInterval.loggableSeconds, format: .fixed(precision: 3), privacy: .public)s, \
            pingTimeout \
            \(openPayload.pingTimeout.loggableSeconds, format: .fixed(precision: 3), privacy: .public)s, \
            maxPayload \(openPayload.maxPayload, privacy: .public) bytes
            """
        )

        maximumPayload = openPayload.maxPayload
        heartbeatDeadline = openPayload.pingInterval + openPayload.pingTimeout
        resetHeartbeat(
            generation: connectionGeneration,
            deadline: heartbeatDeadline ?? .seconds(45)
        )
        try await sendSocketPacket(.connect(namespace: "/", payload: nil), maximumPayload: openPayload.maxPayload)
        startNamespaceTimeout(generation: connectionGeneration)

        try await awaitNamespaceConnection(generation: connectionGeneration)
        namespaceTimeoutTask?.cancel()
        namespaceTimeoutTask = nil
        guard isCurrent(connectionGeneration) else { throw CancellationError() }
        Logger.socketIO.debug("Namespace / connected at generation \(connectionGeneration, privacy: .public)")
        setStatus(.connected)

        try await receiveLoop(generation: connectionGeneration)
    }

    func receive(generation connectionGeneration: UInt64) async throws -> WebSocketMessage {
        do {
            let message = try await webSocket.receive()
            guard isCurrent(connectionGeneration) else { throw CancellationError() }
            return message
        } catch {
            if let failure = consumeForcedFailure(generation: connectionGeneration) {
                throw failure
            }
            guard isCurrent(connectionGeneration) else { throw CancellationError() }
            throw LifecycleFailure.reconnectable(transportFailure(error))
        }
    }

    func failGenerationFromSend(_ connectionGeneration: UInt64, error: any Error) async {
        guard isCurrent(connectionGeneration), forcedFailure == nil else { return }
        forcedFailure = (
            connectionGeneration,
            .reconnectable(transportFailure(error))
        )
        await webSocket.close(code: .internalServerError, reason: nil)
    }

    func resetHeartbeat(generation connectionGeneration: UInt64, deadline: Duration) {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            do {
                try await clock.sleep(for: deadline)
            } catch {
                return
            }
            await self.watchdogExpired(
                generation: connectionGeneration,
                failure: .reconnectable(.heartbeatTimeout)
            )
        }
    }

    func startNamespaceTimeout(generation connectionGeneration: UInt64) {
        namespaceTimeoutTask?.cancel()
        namespaceTimeoutTask = Task {
            do {
                try await clock.sleep(for: namespaceTimeout)
            } catch {
                return
            }
            await self.watchdogExpired(
                generation: connectionGeneration,
                failure: .terminal(.namespaceTimeout)
            )
        }
    }

    func watchdogExpired(generation connectionGeneration: UInt64, failure: LifecycleFailure) async {
        guard isCurrent(connectionGeneration), forcedFailure == nil else { return }
        // Closing the transport unblocks the single receive operation. `receive(generation:)` then substitutes this
        // lifecycle failure for the transport cancellation so reconnect policy sees the actual watchdog result.
        forcedFailure = (connectionGeneration, failure)
        await webSocket.close(code: .internalServerError, reason: nil)
    }

    func consumeForcedFailure(generation connectionGeneration: UInt64) -> LifecycleFailure? {
        guard forcedFailure?.generation == connectionGeneration else { return nil }
        let failure = forcedFailure?.failure
        forcedFailure = nil
        return failure
    }

    func reconnectDelay(attempt: Int) -> Duration {
        let exponent = Double(max(0, attempt - 1))
        let uncapped = reconnectPolicy.initialDelay * pow(reconnectPolicy.multiplier, exponent)
        let capped = min(uncapped, reconnectPolicy.maximumDelay)
        let unit = min(max(randomSource.unitInterval(), 0), 1)
        let factor = 1 + ((unit * 2) - 1) * reconnectPolicy.jitter
        return min(max(.zero, capped * factor), reconnectPolicy.maximumDelay)
    }

    func canReconnect(attempt: Int) -> Bool {
        guard reconnectPolicy.enabled else { return false }
        return reconnectPolicy.maximumAttempts.map { attempt <= $0 } ?? true
    }

    func isCurrent(_ connectionGeneration: UInt64) -> Bool {
        connectionGeneration == generation && !isInvalidated && !isExplicitlyDisconnected
    }

    func closeTransport() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        namespaceTimeoutTask?.cancel()
        namespaceTimeoutTask = nil
        maximumPayload = nil
        heartbeatDeadline = nil
        await webSocket.close(code: .goingAway, reason: nil)
    }

    func finishConnectionLoop(generation connectionGeneration: UInt64) {
        guard connectionGeneration == generation else { return }
        connectionTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        namespaceTimeoutTask?.cancel()
        namespaceTimeoutTask = nil
        maximumPayload = nil
        heartbeatDeadline = nil
        forcedFailure = nil
    }

    func transportFailure(_ error: any Error) -> SocketConnectionFailure {
        if case WebSocketError.transport(let snapshot) = error {
            return .transport(typeName: snapshot.typeName)
        }
        let snapshot = WebSocketErrorSnapshot(error)
        return .transport(typeName: snapshot.typeName)
    }

    func protocolFailure(_ error: any Error) -> SocketConnectionFailure {
        if let protocolError = error as? SocketIOProtocolError {
            return .protocolViolation(protocolError.localizedDescription)
        }
        return .protocolViolation(String(reflecting: type(of: error)))
    }
}
