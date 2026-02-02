//
//  SocketEvent.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
public protocol SocketEvent: Sendable {
    
    static var name: String { get }
    
    associatedtype Schema: Decodable & Sendable
    
}
