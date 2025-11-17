//
//  SocketConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Configuration for socket connections
public struct SocketConfiguration: Sendable {

    /// The URL to connect to
    public let url: URL

    /// Optional authentication token
    public let authToken: String?

    /// Number of reconnection attempts (default: 5)
    public let reconnectAttempts: Int

    /// Time to wait between reconnection attempts in seconds (default: 2)
    public let reconnectWait: TimeInterval

    /// Whether to automatically connect on initialization (default: false)
    public let autoConnect: Bool

    /// Whether to enable compression (default: false)
    public let compress: Bool

    public init(
        url: URL,
        authToken: String? = nil,
        reconnectAttempts: Int = 5,
        reconnectWait: TimeInterval = 2,
        autoConnect: Bool = false,
        compress: Bool = false
    ) {
        self.url = url
        self.authToken = authToken
        self.reconnectAttempts = reconnectAttempts
        self.reconnectWait = reconnectWait
        self.autoConnect = autoConnect
        self.compress = compress
    }

    /// Converts configuration to SocketIO configuration array
    internal func toSocketIOConfig() -> SocketIOClientConfiguration {
        var config: SocketIOClientConfiguration = [
            .reconnectAttempts(reconnectAttempts),
            .reconnectWait(Int(reconnectWait))
        ]

        if compress {
            config.insert(.compress)
        }

        // Add auth token if provided
        if let authToken = authToken {
            config.insert(.connectParams(["token": authToken]))
        }

        return config
    }
}
