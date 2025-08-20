//
//  EmptyBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-12.
//

import Foundation
import SocketIO

public struct EmptyBody: Decodable, Sendable {
    
    public init() {}

}

extension EmptyBody: SocketData {
    
    public func socketRepresentation() throws -> SocketData {
        return []
    }

}
