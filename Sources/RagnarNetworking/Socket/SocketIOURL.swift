//
//  SocketIOURL.swift
//  RagnarNetworking
//

import Foundation

/// Builds Socket.IO WebSocket URLs from HTTP(S) server URLs.
enum SocketIOURL {

    /// Converts an HTTP/HTTPS server URL to a Socket.IO WebSocket URL, joining `path` onto
    /// the server URL's existing path (rather than discarding it) and appending the `EIO`
    /// and `transport` query items while preserving unrelated query items already present.
    static func webSocketURL(for serverURL: URL, path: String = "socket.io") -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch serverURL.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"

        case "https":
            components.scheme = "wss"

        default:
            return nil
        }
        joinPath(path, to: &components)

        var queryItems = (components.queryItems ?? []).filter {
            $0.name != "EIO" && $0.name != "transport"
        }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ])
        components.queryItems = queryItems

        return components.url
    }

    /// Joins `path` onto `components`'s existing path, matching
    /// `RequestBuilder.applyPath`'s semantics so the two halves of the package agree
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
