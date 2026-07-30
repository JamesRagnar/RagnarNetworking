//
//  SocketIOClient+FrameHandling.swift
//  RagnarNetworking
//

import Foundation

// MARK: - Private: Heartbeat and Socket.IO Packet Handling

extension SocketIOClient {

    /// Restarts the heartbeat watchdog. Call on every inbound frame - any frame indicates
    /// the connection is alive, and only sustained silence should be treated as a fault.
    func resetHeartbeat(generation: UInt64) {
        heartbeatTask?.cancel()
        let deadline = pingInterval + pingTimeout
        heartbeatTask = Task {
            do {
                try await clock.sleep(for: deadline)
            } catch {
                // Cancelled because a newer frame reset the watchdog, or the connection
                // was torn down - not a timeout.
                return
            }
            heartbeatTimedOut(generation: generation)
        }
    }

    /// No inbound frame arrived within `pingInterval + pingTimeout`. Cancels the transport
    /// task so its in-flight `receive()` fails, which routes through the connection loop's
    /// existing disconnect/reconnect handling exactly as a real network failure would.
    func heartbeatTimedOut(generation: UInt64) {
        guard generation == connectionGeneration else { return }
        rnLog(
            .socket,
            logging: logging,
            level: .error,
            "heartbeat timeout - no frames received within pingInterval + pingTimeout"
        )
        currentTask?.cancel(with: .abnormalClosure, reason: nil)
    }

    func handleSocketIOPacket(_ type: SocketIOPacketType?, payload: Substring) async {
        switch type {
        case .connect:
            // Socket.IO CONNECT ack
            rnLog(.socket, logging: logging, "connect")
            setStatus(.connected)

        case .connectError:
            // Socket.IO CONNECT_ERROR - the server rejected the connection. Reconnecting
            // with the same credentials would only be rejected again, so this is terminal
            // for the current attempt rather than a transient fault to retry.
            let reason = parseConnectError(String(payload))
            rnLog(.socket, logging: logging, level: .error, "connect_error: \(reason)")
            failConnection(reason: reason)

        case .event:
            if let (name, data) = parseEvent(String(payload)) {
                rnLog(.socket, logging: logging, "event: \(name)")
                let eventData = data ?? Data("{}".utf8)
                if let conts = eventContinuations[name] {
                    for cont in conts.values { cont.yield(eventData) }
                }
            } else {
                rnLog(.socket, logging: logging, "ignored malformed event frame")
            }

        case .disconnect, .ack, .binaryEvent, .binaryAck, nil:
            rnLog(.socket, logging: logging, "ignored unhandled Socket.IO packet \(String(describing: type))")
        }
    }
}

// MARK: - Private: Frame Parsing

extension SocketIOClient {

    func parseEvent(_ payload: String) -> (name: String, payload: Data?)? {
        guard
            let data = payload.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let name = array.first as? String
        else { return nil }

        let eventPayload: Data? = array.count > 1
            ? try? JSONSerialization.data(withJSONObject: array[1], options: .fragmentsAllowed)
            : nil

        return (name, eventPayload)
    }

    /// Parses `pingInterval`/`pingTimeout` (milliseconds) from an Engine.IO `open` payload.
    /// Leaves the current values in place if the payload is absent or unparseable.
    func parseOpenPayload(_ text: String) {
        let json = String(text.dropFirst(1))
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let intervalMS = object["pingInterval"] as? Int {
            pingInterval = .milliseconds(intervalMS)
        }
        if let timeoutMS = object["pingTimeout"] as? Int {
            pingTimeout = .milliseconds(timeoutMS)
        }
    }

    func parseConnectError(_ payload: String) -> String {
        guard let braceIndex = payload.firstIndex(of: "{") else {
            return payload.isEmpty ? "Connection rejected by server" : payload
        }

        let json = String(payload[braceIndex...])
        guard let data = json.data(using: .utf8) else {
            rnLog(.socket, logging: logging, level: .error, "connect_error payload was not valid UTF-8: \(json)")
            return "Connection rejected by server"
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let message = object?["message"] as? String else {
                rnLog(
                    .socket,
                    logging: logging,
                    level: .error,
                    "connect_error payload had no \"message\" field: \(json)"
                )
                return "Connection rejected by server"
            }
            return message
        } catch {
            rnLog(
                .socket,
                logging: logging,
                level: .error,
                "failed to parse connect_error payload \(json): \(error)"
            )
            return "Connection rejected by server"
        }
    }
}
