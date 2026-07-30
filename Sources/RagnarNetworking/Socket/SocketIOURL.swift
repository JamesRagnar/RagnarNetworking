//
//  SocketIOURL.swift
//  RagnarNetworking
//

import Foundation

/// Builds Socket.IO WebSocket URLs from HTTP(S) server URLs.
enum SocketIOURL {

    /// Converts an HTTP/HTTPS server URL to a Socket.IO WebSocket URL, joining `path` onto
    /// the server URL's existing path (rather than discarding it) and appending the `EIO`
    /// and `transport` query items to any query items already present.
    static func webSocketURL(for serverURL: URL, path: String = "socket.io") -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        joinPath(path, to: &components)

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ])
        components.queryItems = queryItems

        return components.url
    }

    /// Joins `path` onto `components`'s existing path, matching
    /// `InterfaceConstructor.applyPath`'s semantics so the two halves of the package agree
    /// on how a base URL's path combines with a relative path.
    private static func joinPath(_ path: String, to components: inout URLComponents) {
        let trailingSlashPath = path.hasSuffix("/") ? path : path + "/"
        let basePath = components.path

        if basePath.isEmpty || basePath == "/" {
            components.path = trailingSlashPath.hasPrefix("/") ? trailingSlashPath : "/" + trailingSlashPath
            return
        }

        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let trimmedPath = trailingSlashPath.hasPrefix("/") ? String(trailingSlashPath.dropFirst()) : trailingSlashPath
        components.path = "\(trimmedBase)/\(trimmedPath)"
    }

}
