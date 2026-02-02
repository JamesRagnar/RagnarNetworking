//
//  EmptyBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-12.
//

import Foundation
import SocketIO

/// Represents a no-payload socket event body.
///
/// Example custom body conformance:
/// ```swift
/// struct ChatMessage: Codable, Sendable {
///     let message: String
/// }
///
/// extension ChatMessage: SocketData {
///     public func socketRepresentation() throws -> SocketData {
///         let data = try JSONEncoder().encode(self)
///         return try JSONSerialization.jsonObject(with: data) as! SocketData
///     }
/// }
/// ```
public struct EmptyBody: Decodable, Sendable {
    
    public init() {}

}

extension EmptyBody: SocketData {
    
    public func socketRepresentation() throws -> SocketData {
        return []
    }

}
