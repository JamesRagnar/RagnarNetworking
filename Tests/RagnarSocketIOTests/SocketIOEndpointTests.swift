import Foundation
@testable import RagnarSocketIO
import Testing

@Suite("Socket.IO Endpoint")
struct SocketIOEndpointTests {
    @Test(
        "Server endpoint resolves its scheme",
        arguments: [
            ("http://example.com", "ws"),
            ("https://example.com", "wss")
        ]
    )
    func scheme(input: String, expected: String) throws {
        let endpoint = SocketIOEndpoint.server(try #require(URL(string: input)))
        let request = try endpoint.resolve()
        #expect(request.url?.scheme == expected)
    }

    @Test(
        "Server endpoint joins and normalizes paths",
        arguments: [
            ("https://example.com", "/socket.io/", "/socket.io/"),
            ("https://example.com/api", "socket.io", "/api/socket.io/"),
            ("https://example.com/api/", "/custom/", "/api/custom/")
        ]
    )
    func path(input: String, socketPath: String, expected: String) throws {
        let endpoint = SocketIOEndpoint.server(try #require(URL(string: input)), path: socketPath)
        let request = try endpoint.resolve()
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.path == expected)
    }

    @Test("Server endpoint replaces protocol query items and preserves unrelated items")
    func queryItems() throws {
        let url = try #require(URL(string: "https://example.com?token=value&EIO=3&EIO=2&transport=polling"))
        let request = try SocketIOEndpoint.server(url).resolve()
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })

        #expect(components.queryItems == [
            URLQueryItem(name: "token", value: "value"),
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ])
    }

    @Test("Server endpoint applies headers")
    func headers() throws {
        let url = try #require(URL(string: "https://example.com"))
        let request = try SocketIOEndpoint.server(url, headers: ["Authorization": "Bearer token"]).resolve()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test("Complete requests are preserved")
    func completeRequest() throws {
        let url = try #require(URL(string: "wss://example.com/custom?EIO=4&transport=websocket&token=value"))
        var input = URLRequest(url: url)
        input.httpMethod = "GET"
        input.setValue("value", forHTTPHeaderField: "X-Test")

        #expect(try SocketIOEndpoint.request(input).resolve() == input)
    }

    @Test(
        "Invalid server endpoints fail",
        arguments: [
            "ws://example.com",
            "ftp://example.com",
            "https:///socket.io/"
        ]
    )
    func invalidServer(input: String) throws {
        let url = try #require(URL(string: input))
        #expect(throws: SocketIOProtocolError.invalidEndpoint) {
            try SocketIOEndpoint.server(url).resolve()
        }
    }

    @Test(
        "Complete requests require Engine.IO 4",
        arguments: [
            "wss://example.com?transport=websocket",
            "wss://example.com?EIO=3&transport=websocket",
            "wss://example.com?EIO=4&EIO=4&transport=websocket"
        ]
    )
    func engineVersion(input: String) throws {
        let url = try #require(URL(string: input))
        #expect(throws: SocketIOProtocolError.self) {
            try SocketIOEndpoint.request(URLRequest(url: url)).resolve()
        }
    }

    @Test(
        "Complete requests require direct WebSocket transport",
        arguments: [
            "wss://example.com?EIO=4",
            "wss://example.com?EIO=4&transport=polling",
            "wss://example.com?EIO=4&transport=websocket&transport=websocket"
        ]
    )
    func transport(input: String) throws {
        let url = try #require(URL(string: input))
        #expect(throws: SocketIOProtocolError.self) {
            try SocketIOEndpoint.request(URLRequest(url: url)).resolve()
        }
    }
}
