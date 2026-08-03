import Foundation

/// Configuration used to resolve a direct-WebSocket Socket.IO connection request.
public enum SocketIOEndpoint: Sendable, Equatable {
    /// An HTTP or HTTPS server URL, Socket.IO path, and optional handshake headers.
    ///
    /// Resolution maps the scheme to WS or WSS, joins `path` onto the server URL's existing path, preserves unrelated
    /// query items, and replaces protocol query items with `EIO=4&transport=websocket`.
    case server(
        URL,
        path: String = "/socket.io/",
        headers: [String: String] = [:]
    )
    /// A complete WS or WSS request containing exactly `EIO=4&transport=websocket`.
    case request(URLRequest)

    func resolve() throws -> URLRequest {
        switch self {
        case .server(let serverURL, let path, let headers):
            return try Self.resolve(serverURL: serverURL, path: path, headers: headers)

        case .request(let request):
            try Self.validate(request)
            return request
        }
    }

    private static func resolve(
        serverURL: URL,
        path: String,
        headers: [String: String]
    ) throws -> URLRequest {
        guard
            var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            let host = components.host,
            !host.isEmpty
        else {
            throw SocketIOProtocolError.invalidEndpoint
        }

        switch scheme {
        case "http":
            components.scheme = "ws"

        case "https":
            components.scheme = "wss"

        default:
            throw SocketIOProtocolError.invalidEndpoint
        }

        components.path = joinedPath(prefix: components.path, socketPath: path)
        components.queryItems = protocolQueryItems(replacing: components.queryItems ?? [])

        guard let url = components.url else {
            throw SocketIOProtocolError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private static func validate(_ request: URLRequest) throws {
        guard
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "ws" || scheme == "wss",
            let host = components.host,
            !host.isEmpty
        else {
            throw SocketIOProtocolError.invalidEndpoint
        }

        let engineVersions = values(named: "EIO", in: components.queryItems ?? [])
        guard engineVersions == ["4"] else {
            throw SocketIOProtocolError.unsupportedEngineIOVersion(engineVersions.first.flatMap { $0 })
        }

        let transports = values(named: "transport", in: components.queryItems ?? [])
        guard transports == ["websocket"] else {
            throw SocketIOProtocolError.unsupportedTransport(transports.first.flatMap { $0 })
        }
    }

    private static func joinedPath(prefix: String, socketPath: String) -> String {
        let prefixComponents = prefix.split(separator: "/")
        let socketComponents = socketPath.split(separator: "/")
        return "/" + (prefixComponents + socketComponents).joined(separator: "/") + "/"
    }

    private static func protocolQueryItems(replacing queryItems: [URLQueryItem]) -> [URLQueryItem] {
        queryItems.filter { item in
            item.name != "EIO" && item.name != "transport"
        } + [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
    }

    private static func values(named name: String, in queryItems: [URLQueryItem]) -> [String?] {
        queryItems.filter { $0.name == name }.map(\.value)
    }
}
