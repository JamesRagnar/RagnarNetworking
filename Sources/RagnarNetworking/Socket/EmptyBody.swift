//
//  EmptyBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-12.
//

import Foundation

/// Represents a no-payload socket event body.
///
/// Example custom body conformance:
/// ```swift
/// struct ChatMessage: Codable, Sendable {
///     let message: String
/// }
///
/// extension ChatMessage: SocketPayload {}
/// ```
public struct EmptyBody: Codable, Sendable, SocketPayload {
    
    public init() {}

}
    
public extension EmptyBody {
    func socketPayload() throws -> SocketPayloadValue {
        .dictionary([:])
    }
}
