import Foundation
import OSLog
import RagnarWebSocket

extension SocketIOClient {
    func awaitNamespaceConnection(generation connectionGeneration: UInt64) async throws {
        while isCurrent(connectionGeneration) {
            guard let packet = try await receiveEnginePacket(generation: connectionGeneration) else { continue }
            switch packet {
            case .ping(let payload):
                try await handlePing(payload, generation: connectionGeneration)

            case .message(let payload):
                guard let socketPacket = decodeSocketPacket(payload) else { continue }
                if try handleNamespaceSocketPacket(socketPacket) { return }

            case .close:
                throw LifecycleFailure.reconnectable(.protocolViolation("Engine.IO transport closed"))

            case .open:
                throw LifecycleFailure.reconnectable(.protocolViolation("Repeated Engine.IO OPEN"))

            case .pong:
                continue

            case .upgrade, .noop:
                discard("unsupported Engine.IO packet before namespace connection")
            }
        }
        throw CancellationError()
    }

    /// Returns whether the packet completed the default namespace connection.
    ///
    /// Anything this method discards is backstopped by `namespaceTimeout`, which fails the attempt if the server never
    /// completes the handshake.
    func handleNamespaceSocketPacket(_ packet: SocketIOPacket) throws -> Bool {
        switch packet {
        case .connect(let namespace, _):
            guard namespace == "/" else {
                discard("CONNECT for a non-default namespace", detail: namespace)
                return false
            }
            return true

        case .connectError(let namespace, let payload):
            guard namespace == "/" else {
                discard("CONNECT_ERROR for a non-default namespace", detail: namespace)
                return false
            }
            throw LifecycleFailure.terminal(.connectError(message: connectErrorMessage(payload)))

        case .disconnect(let namespace):
            guard namespace == "/" else {
                discard("DISCONNECT for a non-default namespace", detail: namespace)
                return false
            }
            throw LifecycleFailure.serverDisconnect

        case .event, .acknowledgement, .binaryEvent, .binaryAcknowledgement:
            discard("Socket.IO packet received before namespace connection")
            return false
        }
    }

    func receiveLoop(generation connectionGeneration: UInt64) async throws {
        while isCurrent(connectionGeneration) {
            guard let packet = try await receiveEnginePacket(generation: connectionGeneration) else { continue }
            switch packet {
            case .ping(let payload):
                try await handlePing(payload, generation: connectionGeneration)

            case .message(let payload):
                guard let socketPacket = decodeSocketPacket(payload) else { continue }
                try handleConnectedSocketPacket(socketPacket)

            case .close:
                throw LifecycleFailure.reconnectable(.protocolViolation("Engine.IO transport closed"))

            case .open:
                throw LifecycleFailure.reconnectable(.protocolViolation("Repeated Engine.IO OPEN"))

            case .pong:
                continue

            case .upgrade, .noop:
                discard("unsupported Engine.IO packet")
            }
        }
        throw CancellationError()
    }

    /// Returns the next interpretable Engine.IO packet, or `nil` when the received frame was discarded.
    ///
    /// WebSocket delivers whole frames, so a frame this client cannot interpret carries no information about the next
    /// one. Discarding it keeps the connection usable.
    func receiveEnginePacket(generation connectionGeneration: UInt64) async throws -> EngineIOPacket? {
        let message = try await receive(generation: connectionGeneration)
        guard case .text(let text) = message else {
            discard("binary Engine.IO frame")
            return nil
        }
        do {
            return try EngineIOCodec.decode(text)
        } catch {
            discard("undecodable Engine.IO frame", detail: text)
            return nil
        }
    }

    func discard(_ reason: String, detail: String? = nil) {
        let suffix = detail.map { " (\($0))" } ?? ""
        Logger.socketIO.error("Discarded \(reason, privacy: .public)\(suffix, privacy: .private)")
    }

    func handlePing(_ payload: String, generation connectionGeneration: UInt64) async throws {
        guard isCurrent(connectionGeneration) else { throw CancellationError() }
        guard let maximumPayload else { throw LifecycleFailure.terminal(.protocolViolation("Missing OPEN state")) }

        resetHeartbeat(generation: connectionGeneration, deadline: currentHeartbeatDeadline())
        Logger.socketIO.debug("Engine.IO PING received, heartbeat rearmed")
        do {
            let pong = try EngineIOCodec.encode(.pong(payload))
            try EngineIOPacket.pong(payload).validateMessageSize(maximum: maximumPayload)
            try await webSocket.send(.text(pong))
        } catch {
            throw LifecycleFailure.reconnectable(transportFailure(error))
        }
    }

    func currentHeartbeatDeadline() -> Duration {
        heartbeatDeadline ?? .seconds(45)
    }

    func sendSocketPacket(_ packet: SocketIOPacket, maximumPayload: Int) async throws {
        let enginePacket: EngineIOPacket
        do {
            let socketPayload = try SocketIOCodec.encode(packet)
            enginePacket = .message(socketPayload)
            try enginePacket.validateMessageSize(maximum: maximumPayload)
        } catch {
            throw LifecycleFailure.terminal(protocolFailure(error))
        }
        do {
            try await webSocket.send(.text(try EngineIOCodec.encode(enginePacket)))
        } catch {
            throw LifecycleFailure.reconnectable(transportFailure(error))
        }
    }

    func decodeSocketPacket(_ payload: String) -> SocketIOPacket? {
        do {
            return try SocketIOCodec.decode(payload)
        } catch {
            discard("undecodable Socket.IO packet", detail: payload)
            return nil
        }
    }

    func handleConnectedSocketPacket(_ packet: SocketIOPacket) throws {
        switch packet {
        case .event(let namespace, let acknowledgementID, let name, let arguments):
            guard namespace == "/" else {
                discard("event for a non-default namespace", detail: namespace)
                return
            }
            guard acknowledgementID == nil else {
                discard("acknowledgement-bearing event", detail: name)
                return
            }
            fanOut(eventName: name, arguments: arguments)

        case .disconnect(let namespace):
            guard namespace == "/" else {
                discard("DISCONNECT for a non-default namespace", detail: namespace)
                return
            }
            throw LifecycleFailure.serverDisconnect

        case .connectError(let namespace, let payload):
            guard namespace == "/" else {
                discard("CONNECT_ERROR for a non-default namespace", detail: namespace)
                return
            }
            throw LifecycleFailure.terminal(.connectError(message: connectErrorMessage(payload)))

        case .connect:
            discard("repeated Socket.IO CONNECT")

        case .acknowledgement:
            discard("Socket.IO acknowledgement")

        case .binaryEvent, .binaryAcknowledgement:
            discard("Socket.IO binary packet")
        }
    }

    func fanOut(eventName: String, arguments: [SocketIOArgument]) {
        Logger.socketIO.debug("Received event \(eventName, privacy: .private)")
        guard let subscriptions = eventSubscriptions[eventName] else {
            Logger.socketIO.debug("Dropped event \(eventName, privacy: .private): no subscriptions")
            return
        }
        var terminated: [UUID] = []
        for (identifier, continuation) in subscriptions where !continuation.yield(arguments) {
            terminated.append(identifier)
        }
        for identifier in terminated {
            removeEventSubscription(id: identifier, eventName: eventName)
        }
    }

    func connectErrorMessage(_ payload: SocketIOArgument) -> String? {
        struct Payload: Decodable {
            let message: String?
        }
        guard let message = try? payload.decode(Payload.self).message else {
            let raw = String(bytes: payload.data, encoding: .utf8) ?? "not UTF-8"
            Logger.socketIO.error("Undecodable connect_error payload (\(raw, privacy: .private))")
            return nil
        }
        return message
    }
}
