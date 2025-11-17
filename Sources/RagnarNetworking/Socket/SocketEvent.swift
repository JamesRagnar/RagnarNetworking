//
//  SocketEvent.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Protocol defining a socket event with associated types for receiving and sending
public protocol SocketEvent: Sendable {

    /// The name of the socket event
    static var name: String { get }

    /// The schema for receiving/decoding events
    associatedtype Schema: Decodable & Sendable

    /// The payload type for sending events (defaults to Schema)
    associatedtype Payload: Sendable = Schema

    /// The response type for acknowledgments (defaults to EmptyBody)
    associatedtype Response: Decodable & Sendable = EmptyBody

}
