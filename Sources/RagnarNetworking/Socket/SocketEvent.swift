//
//  SocketEvent.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation

public protocol SocketInboundEvent: Sendable {

    static var name: String { get }

    associatedtype Payload: Decodable & Sendable

}

public protocol SocketOutboundEvent: Sendable {

    static var name: String { get }

    associatedtype Payload: SocketPayload & Sendable

}
