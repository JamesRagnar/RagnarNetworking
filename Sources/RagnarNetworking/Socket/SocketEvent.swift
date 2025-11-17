//
//  SocketEvent.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Defines the contract for a socket.io event, including its name and associated data types.
///
/// Conform to this protocol to create type-safe socket event definitions. The protocol allows
/// you to specify different types for receiving events, sending events, and handling acknowledgments.
///
/// Example:
/// ```swift
/// struct ChatMessageEvent: SocketEvent {
///     static let name = "chat:message"
///
///     // Type received from server
///     struct Schema: Codable, Sendable {
///         let message: String
///         let userId: Int
///     }
///
///     // Type sent to server (defaults to Schema if not specified)
///     struct Payload: Codable, Sendable, SocketData {
///         let message: String
///     }
///
///     // Acknowledgment type (defaults to EmptyBody if not specified)
///     struct Response: Codable, Sendable {
///         let messageId: String
///     }
/// }
/// ```
public protocol SocketEvent: Sendable {

    /// The socket.io event name (e.g., "chat:message", "user:connected")
    static var name: String { get }

    /// The type received when the server emits this event
    associatedtype Schema: Decodable & Sendable

    /// The type sent when emitting this event to the server (defaults to Schema)
    associatedtype Payload: Sendable = Schema

    /// The type received in acknowledgment responses (defaults to EmptyBody)
    associatedtype Response: Decodable & Sendable = EmptyBody

}
