//
//  ServerConfigurationTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("ServerConfiguration Tests", .timeLimit(.minutes(1)))
struct ServerConfigurationTests {

    private struct Params: InterfaceRequest {
        let method: RequestMethod = .get
        let path: String = "/test"
        let queryItems: [URLQueryItem]? = nil
        var headers: [String: String]?
        let body: EmptyBody = EmptyBody()
        let authentication: AuthenticationScheme? = nil
    }

    // MARK: - Header Resolution

    @Test("resolvedHeaders returns the default headers when a request declares none")
    func testResolvedHeadersWithoutRequestHeaders() {
        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            defaultHeaders: ["X-App-Version": "1.0", "Accept-Language": "en-US"]
        )

        let resolved = config.resolvedHeaders(for: Params(headers: nil))

        #expect(resolved == ["X-App-Version": "1.0", "Accept-Language": "en-US"])
    }

    @Test("resolvedHeaders lets a request header override a default of the same name")
    func testResolvedHeadersRequestWins() {
        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            defaultHeaders: ["X-App-Version": "1.0", "Accept-Language": "en-US"]
        )

        let resolved = config.resolvedHeaders(for: Params(headers: ["X-App-Version": "2.0"]))

        #expect(resolved == ["X-App-Version": "2.0", "Accept-Language": "en-US"])
    }

    @Test("resolvedHeaders overrides case-insensitively, leaving a single header")
    func testResolvedHeadersCaseInsensitiveOverride() {
        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            defaultHeaders: ["content-type": "application/xml"]
        )

        let resolved = config.resolvedHeaders(for: Params(headers: ["Content-Type": "application/json"]))

        #expect(resolved.count == 1)
        #expect(resolved["Content-Type"] == "application/json")
    }

    @Test("resolvedHeaders merges the request's headers when no default collides")
    func testResolvedHeadersMergesDistinctNames() {
        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            defaultHeaders: ["X-App-Version": "1.0"]
        )

        let resolved = config.resolvedHeaders(for: Params(headers: ["X-Request-ID": "abc"]))

        #expect(resolved == ["X-App-Version": "1.0", "X-Request-ID": "abc"])
    }

    @Test("resolvedHeaders(overriddenBy:) overlays an arbitrary header set, case-insensitively")
    func testResolvedHeadersOverriddenBy() {
        // The primitive a custom RequestBuilder reaches for when its headers do not come
        // from InterfaceRequest; merging by hand would reintroduce case-sensitive duplicates.
        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            defaultHeaders: ["accept-language": "en-US", "X-App-Version": "1.0"]
        )

        let resolved = config.resolvedHeaders(overriddenBy: ["Accept-Language": "fr-FR"])

        #expect(resolved.count == 2)
        #expect(resolved["Accept-Language"] == "fr-FR")
        #expect(resolved["X-App-Version"] == "1.0")
    }

    @Test("resolvedHeaders(overriddenBy:) returns the defaults for nil or empty overrides")
    func testResolvedHeadersOverriddenByEmpty() {
        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            defaultHeaders: ["X-App-Version": "1.0"]
        )

        #expect(config.resolvedHeaders(overriddenBy: nil) == ["X-App-Version": "1.0"])
        #expect(config.resolvedHeaders(overriddenBy: [:]) == ["X-App-Version": "1.0"])
    }

    @Test("resolvedHeaders returns an empty set when nothing is configured or requested")
    func testResolvedHeadersEmpty() {
        let config = ServerConfiguration(url: URL(string: "https://api.example.com")!)

        #expect(config.resolvedHeaders(for: Params(headers: nil)).isEmpty)
    }

    // MARK: - Request Context

    @Test("RequestContext forwards the configuration's coders")
    func testRequestContextForwardsCoders() {
        struct Payload: Codable {
            let userId: Int
        }

        let config = ServerConfiguration(
            url: URL(string: "https://api.example.com")!,
            requestEncoder: RequestEncoder(keyEncodingStrategy: .convertToSnakeCase),
            responseDecoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
        )
        let context = RequestContext(configuration: config, credential: nil)

        let data = try! context.requestEncoder.makeJSONEncoder().encode(Payload(userId: 1))
        let json = try! JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["user_id"] as? Int == 1)

        let snakeCaseJSON = #"{"user_id": 2}"#.data(using: .utf8)!
        let decoded = try! context.responseDecoder.makeJSONDecoder().decode(Payload.self, from: snakeCaseJSON)
        #expect(decoded.userId == 2)
    }

}
