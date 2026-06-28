//
//  SocketIOURL.swift
//  RagnarNetworking
//

import Foundation

/// Builds Socket.IO WebSocket URLs from HTTP(S) server URLs.
public enum SocketIOURL {

    public static func webSocketURL(for serverURL: URL) -> URL? {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/socket.io/"
        components?.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
        return components?.url
    }

}

