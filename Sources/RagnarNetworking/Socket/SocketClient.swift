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

    func events<E: SocketEvent>(for type: E.Type) -> AsyncStream<E.Schema>
    func statusUpdates() -> AsyncStream<SocketConnectionStatus>

}

