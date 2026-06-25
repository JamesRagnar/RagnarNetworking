//
//  SocketEmptyBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-12.
//

import Foundation

/// Sentinel `Schema` type for `SocketEvent` conformances that carry no payload.
///
/// Use this as `associatedtype Schema` when your event has no body. The corresponding
/// `emit(_:)` overload accepts no payload argument.
public struct SocketEmptyBody: Decodable, Sendable {

    public init() {}

}
