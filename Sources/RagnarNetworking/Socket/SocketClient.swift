//
//  SocketClient.swift
//  RagnarNetworking
//

import Foundation

/// Public transport-facing socket connection states.
public enum SocketConnectionStatus: Sendable, Equatable {

    case disconnected
    case connecting
    case connected

    /// The server rejected the connection (Socket.IO `CONNECT_ERROR`), for example due
    /// to invalid or expired credentials. Terminal for the current connection attempt:
    /// automatic reconnection is not attempted, since the same credentials would be
    /// rejected again. Call `connect()` or `reconnect(to:)` explicitly once the
    /// underlying cause (such as a stale token) has been addressed.
    case failed(reason: String)

}

/// Abstract socket transport used by higher-level packages.
///
/// Conforming types own connection lifecycle, typed event streams, and event emission.
/// The abstraction intentionally stays at the typed Socket.IO transport layer rather than
/// exposing lower-level frame parsing details.
public protocol SocketClient: Actor {

    func connect() async
    func disconnect()
    func reconnect(to newURL: URL) async
    func invalidate()

    func emit<E: SocketEvent>(_ type: E.Type, _ payload: E.Schema) async throws
        where E.Schema: Encodable & Sendable
    func emit<E: SocketEvent>(_ type: E.Type) async throws
        where E.Schema == SocketEmptyBody

    func events<E: SocketEvent>(
        for type: E.Type,
        bufferingPolicy: AsyncStream<E.Schema>.Continuation.BufferingPolicy
    ) -> AsyncStream<E.Schema>
    func statusUpdates() -> AsyncStream<SocketConnectionStatus>

}

extension SocketClient {

    /// Convenience overload defaulting to `.bufferingNewest(64)` - a consumer that falls
    /// behind drops the oldest unread events rather than growing without bound.
    public func events<E: SocketEvent>(for type: E.Type) -> AsyncStream<E.Schema> {
        events(for: type, bufferingPolicy: .bufferingNewest(64))
    }

}
