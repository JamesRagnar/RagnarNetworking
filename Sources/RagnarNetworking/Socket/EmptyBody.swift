//
//  EmptyBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-12.
//

import Foundation
import SocketIO

/// Represents an empty payload or response in socket events.
///
/// Use this type when a socket event has no associated data, either when sending
/// events without payloads or when acknowledgments don't return data.
///
/// This is the default `Response` type for `SocketEvent` when acknowledgments
/// are not needed.
public struct EmptyBody: Decodable, Sendable {

    public init() {}

}

extension EmptyBody: SocketData {

    public func socketRepresentation() throws -> SocketData {
        return []
    }

}
