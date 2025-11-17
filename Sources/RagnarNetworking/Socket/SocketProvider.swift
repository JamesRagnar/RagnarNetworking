//
//  SocketProvider.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Abstracts socket.io operations to enable testing and dependency injection.
///
/// This protocol wraps the essential socket.io client methods, allowing `SocketService`
/// to work with any conforming type. `SocketIOClient` conforms to this protocol automatically,
/// and you can provide mock implementations for testing.
public protocol SocketProvider {

    /// The socket's unique session identifier
    var sid: String? { get }

    /// Current connection status
    var status: SocketIOStatus { get }

    /// Initiate connection to the server
    func connect(withPayload payload: [String: Any]?)

    /// Disconnect from the server
    func disconnect()

    /// Emit an event to the server
    func emit(_ event: String, _ items: any SocketData..., completion: (() -> ())?)

    /// Emit an event and receive an acknowledgment callback
    func emitWithAck(_ event: String, _ items: any SocketData...) -> OnAckCallback

    /// Register a listener for a specific event
    func on(_ event: String, callback: @escaping NormalCallback) -> UUID

    /// Register a listener for socket lifecycle events
    func on(clientEvent event: SocketClientEvent, callback: @escaping NormalCallback) -> UUID

    /// Remove a listener by its unique identifier
    func off(id: UUID)

    /// Remove all listeners for a specific event
    func off(_ event: String)
}

// MARK: - SocketIOClient Conformance

extension SocketIOClient: SocketProvider {
    // SocketIOClient already implements all required methods
}
