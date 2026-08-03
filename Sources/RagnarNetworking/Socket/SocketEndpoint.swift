//
//  SocketEndpoint.swift
//  RagnarNetworking
//

import Foundation

/// Describes how a Socket.IO connection endpoint should be resolved.
public enum SocketEndpoint: Sendable, Equatable {

    /// An HTTP/HTTPS server URL that still needs Socket.IO path and query derivation.
    case server(URL, path: String = "socket.io")

    /// A complete WS/WSS Socket.IO URL that should be used verbatim.
    case webSocket(URL)

    func resolvedWebSocketURL() throws -> URL {
        switch self {
        case .server(let serverURL, let path):
            guard let scheme = serverURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                throw SocketEndpointError.unsupportedServerScheme(serverURL.scheme)
            }
            guard serverURL.host != nil else {
                throw SocketEndpointError.missingHost
            }
            guard let webSocketURL = SocketIOURL.webSocketURL(for: serverURL, path: path) else {
                throw SocketEndpointError.invalidURL
            }
            return webSocketURL

        case .webSocket(let webSocketURL):
            guard let scheme = webSocketURL.scheme?.lowercased(), ["ws", "wss"].contains(scheme) else {
                throw SocketEndpointError.unsupportedWebSocketScheme(webSocketURL.scheme)
            }
            guard webSocketURL.host != nil else {
                throw SocketEndpointError.missingHost
            }
            return webSocketURL
        }
    }
}

/// Errors produced while resolving a ``SocketEndpoint``.
public enum SocketEndpointError: LocalizedError, Sendable, Equatable {

    /// A server endpoint did not use HTTP or HTTPS.
    case unsupportedServerScheme(String?)

    /// A complete WebSocket endpoint did not use WS or WSS.
    case unsupportedWebSocketScheme(String?)

    /// The endpoint URL was not absolute.
    case missingHost

    /// URL components could not produce the derived WebSocket URL.
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .unsupportedServerScheme(let scheme):
            return "Socket server URLs require an HTTP or HTTPS scheme, not \(scheme ?? "no scheme")."

        case .unsupportedWebSocketScheme(let scheme):
            return "Socket WebSocket URLs require a WS or WSS scheme, not \(scheme ?? "no scheme")."

        case .missingHost:
            return "Socket endpoints require a host."

        case .invalidURL:
            return "The Socket.IO WebSocket URL could not be constructed."
        }
    }
}
