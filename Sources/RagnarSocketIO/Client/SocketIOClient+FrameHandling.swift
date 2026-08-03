import Foundation
import RagnarWebSocket

extension SocketIOClient {
    func awaitNamespaceConnection(generation connectionGeneration: UInt64) async throws {
        while isCurrent(connectionGeneration) {
            let packet = try await receiveEnginePacket(generation: connectionGeneration)
            switch packet {
            case .ping(let payload):
                try await handlePing(payload, generation: connectionGeneration)

            case .pong:
                continue

            case .message(let payload):
                if try handleNamespaceSocketPacket(decodeSocketPacket(payload)) { return }

            case .close:
                throw LifecycleFailure.reconnectable(.protocolViolation("Engine.IO transport closed"))

            case .open:
                throw LifecycleFailure.terminal(.protocolViolation("Repeated Engine.IO OPEN"))

            case .upgrade:
                throw unsupported("Engine.IO transport upgrade")

            case .noop:
                throw unsupported("Engine.IO NOOP")
            }
        }
        throw CancellationError()
    }

    func handleNamespaceSocketPacket(_ packet: SocketIOPacket) throws -> Bool {
        switch packet {
        case .connect(let namespace, _):
            guard namespace == "/" else { throw unsupported("non-default namespace") }
            return true

        case .connectError(let namespace, let payload):
            guard namespace == "/" else { throw unsupported("non-default namespace") }
            throw LifecycleFailure.terminal(.connectError(message: connectErrorMessage(payload)))

        case .event:
            throw LifecycleFailure.terminal(.protocolViolation("Event received before namespace connection"))

        case .disconnect:
            throw LifecycleFailure.serverDisconnect

        case .acknowledgement:
            throw unsupported("Socket.IO acknowledgement")

        case .binaryEvent, .binaryAcknowledgement:
            throw unsupported("Socket.IO binary packet")
        }
    }

    func receiveLoop(generation connectionGeneration: UInt64) async throws {
        while isCurrent(connectionGeneration) {
            let packet = try await receiveEnginePacket(generation: connectionGeneration)
            switch packet {
            case .ping(let payload):
                try await handlePing(payload, generation: connectionGeneration)

            case .pong:
                continue

            case .message(let payload):
                try handleConnectedSocketPacket(try decodeSocketPacket(payload))

            case .close:
                throw LifecycleFailure.reconnectable(.protocolViolation("Engine.IO transport closed"))

            case .open:
                throw LifecycleFailure.terminal(.protocolViolation("Repeated Engine.IO OPEN"))

            case .upgrade:
                throw unsupported("Engine.IO transport upgrade")

            case .noop:
                throw unsupported("Engine.IO NOOP")
            }
        }
        throw CancellationError()
    }

    func receiveEnginePacket(generation connectionGeneration: UInt64) async throws -> EngineIOPacket {
        let message = try await receive(generation: connectionGeneration)
        guard case .text(let text) = message else {
            throw unsupported("binary Engine.IO transport")
        }
        do {
            return try EngineIOCodec.decode(text)
        } catch {
            throw LifecycleFailure.terminal(protocolFailure(error))
        }
    }

    func handlePing(_ payload: String, generation connectionGeneration: UInt64) async throws {
        guard isCurrent(connectionGeneration) else { throw CancellationError() }
        guard let maximumPayload else { throw LifecycleFailure.terminal(.protocolViolation("Missing OPEN state")) }

        resetHeartbeat(generation: connectionGeneration, deadline: currentHeartbeatDeadline())
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

    func decodeSocketPacket(_ payload: String) throws -> SocketIOPacket {
        do {
            return try SocketIOCodec.decode(payload)
        } catch {
            throw LifecycleFailure.terminal(protocolFailure(error))
        }
    }

    func handleConnectedSocketPacket(_ packet: SocketIOPacket) throws {
        switch packet {
        case .event(let namespace, let acknowledgementID, let name, let arguments):
            guard namespace == "/" else { throw unsupported("non-default namespace") }
            guard acknowledgementID == nil else { throw unsupported("acknowledgement-bearing event") }
            fanOut(eventName: name, arguments: arguments)

        case .disconnect(let namespace):
            guard namespace == "/" else { throw unsupported("non-default namespace") }
            throw LifecycleFailure.serverDisconnect

        case .connectError(let namespace, let payload):
            guard namespace == "/" else { throw unsupported("non-default namespace") }
            throw LifecycleFailure.terminal(.connectError(message: connectErrorMessage(payload)))

        case .connect:
            throw LifecycleFailure.terminal(.protocolViolation("Repeated Socket.IO CONNECT"))

        case .acknowledgement:
            throw unsupported("Socket.IO acknowledgement")

        case .binaryEvent, .binaryAcknowledgement:
            throw unsupported("Socket.IO binary packet")
        }
    }

    func fanOut(eventName: String, arguments: [SocketIOArgument]) {
        guard let subscriptions = eventSubscriptions[eventName] else { return }
        var terminated: [UUID] = []
        for (identifier, continuation) in subscriptions where !continuation.yield(arguments) {
            terminated.append(identifier)
        }
        for identifier in terminated {
            removeEventSubscription(id: identifier, eventName: eventName)
        }
    }

    func unsupported(_ capability: String) -> LifecycleFailure {
        .terminal(.unsupportedCapability(capability))
    }

    func connectErrorMessage(_ payload: SocketIOArgument) -> String? {
        struct Payload: Decodable {
            let message: String?
        }
        return try? payload.decode(Payload.self).message
    }
}
