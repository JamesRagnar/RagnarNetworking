//
//  SocketEmptyBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-12.
//

import Foundation
import SocketIO

public struct SocketEmptyBody: Decodable, Sendable {
    
    public init() {}

}

extension SocketEmptyBody: SocketData {
    
    public func socketRepresentation() throws -> SocketData {
        return []
    }

}
