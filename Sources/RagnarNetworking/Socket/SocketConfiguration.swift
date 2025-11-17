//
//  SocketConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation
import SocketIO

/// Configuration options for socket.io connections.
///
/// Encapsulates connection settings including URL, authentication, and reconnection behavior.
/// The configuration is used when initializing a `SocketService` instance.
public struct SocketConfiguration: Sendable {

    /// The socket.io server URL
    public let url: URL

    /// Optional authentication token passed as a connection parameter
    public let authToken: String?

    /// Maximum number of reconnection attempts (-1 for infinite, default: 5)
    public let reconnectAttempts: Int

    /// Delay between reconnection attempts in seconds (default: 2)
    public let reconnectWait: TimeInterval

    /// Whether to enable socket.io compression (default: false)
    public let compress: Bool

    public init(
        url: URL,
        authToken: String? = nil,
        reconnectAttempts: Int = 5,
        reconnectWait: TimeInterval = 2,
        compress: Bool = false
    ) {
        self.url = url
        self.authToken = authToken
        self.reconnectAttempts = reconnectAttempts
        self.reconnectWait = reconnectWait
        self.compress = compress
    }

    internal func toSocketIOConfig() -> SocketIOClientConfiguration {
        var config: SocketIOClientConfiguration = [
            .reconnectAttempts(reconnectAttempts),
            .reconnectWait(Int(reconnectWait))
        ]

        if compress {
            config.insert(.compress)
        }

        if let authToken = authToken {
            config.insert(.connectParams(["token": authToken]))
        }

        return config
    }
}
