//
//  SocketProvider.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Protocol abstracting socket operations for testability
public protocol SocketProvider {

    /// The socket's unique identifier
    var sid: String? { get }

    /// Current connection status
    var status: SocketIOStatus { get }

    /// Connect the socket
    func connect(withPayload payload: [String: Any]?)

    /// Disconnect the socket
    func disconnect()

    /// Emit an event with data
    func emit(_ event: String, _ items: any SocketData..., completion: (() -> ())?)

    /// Emit an event with data and receive acknowledgment
    func emitWithAck(_ event: String, _ items: any SocketData...) -> OnAckCallback

    /// Listen for a specific event
    func on(_ event: String, callback: @escaping NormalCallback) -> UUID

    /// Listen for status changes
    func on(clientEvent event: SocketClientEvent, callback: @escaping NormalCallback) -> UUID

    /// Remove a specific listener by UUID
    func off(id: UUID)

    /// Remove all listeners for a specific event
    func off(_ event: String)
}

// MARK: - SocketIOClient Conformance

extension SocketIOClient: SocketProvider {
    // Protocol conformance is automatic as SocketIOClient already implements all required methods
}
