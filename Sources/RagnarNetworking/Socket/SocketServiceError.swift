//
//  SocketServiceError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-02-08.
//

public enum SocketServiceError: Error, Sendable {
    case invalidMessageType
    case decodingFailed(eventName: String)
    case notConnected
}
