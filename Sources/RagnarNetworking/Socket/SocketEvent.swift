//
//  SocketEvent.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation

/// Describes a Socket.IO event: its wire name and the shape of its payload.
///
/// Conform to this protocol to define a typed socket event. The `Schema` type is
/// decoded from the raw JSON payload received on the wire.
public protocol SocketEvent: Sendable {

    /// The Socket.IO event name as it appears on the wire (e.g. `"connect"`, `"item_updated"`).
    static var name: String { get }

    /// The payload type decoded from the event's JSON body.
    associatedtype Schema: Decodable & Sendable

}
