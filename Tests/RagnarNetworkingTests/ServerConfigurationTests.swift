//
//  ServerConfigurationTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("ServerConfiguration Tests")
struct ServerConfigurationTests {

    @Test("Initializes with URL and auth token")
    func testInitWithAuthToken() {
        let url = URL(string: "https://api.example.com")!
        let token = "test-token-123"

        let config = ServerConfiguration(url: url, authToken: token)

        #expect(config.url == url)
        #expect(config.authToken == token)
    }

    @Test("Initializes with URL only (no auth token)")
    func testInitWithoutAuthToken() {
        let url = URL(string: "https://api.example.com")!

        let config = ServerConfiguration(url: url)

        #expect(config.url == url)
        #expect(config.authToken == nil)
    }

    @Test("Is Sendable")
    func testSendableConformance() {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "token")

        // This compiles, proving Sendable conformance
        let _: any Sendable = config
    }

    @Test("Preserves different URL schemes")
    func testDifferentURLSchemes() {
        let httpURL = URL(string: "http://api.example.com")!
        let httpsURL = URL(string: "https://api.example.com")!
        let customURL = URL(string: "custom://api.example.com")!

        let httpConfig = ServerConfiguration(url: httpURL)
        let httpsConfig = ServerConfiguration(url: httpsURL)
        let customConfig = ServerConfiguration(url: customURL)

        #expect(httpConfig.url.scheme == "http")
        #expect(httpsConfig.url.scheme == "https")
        #expect(customConfig.url.scheme == "custom")
    }

    @Test("Handles URLs with paths and query parameters")
    func testURLWithPathAndQuery() {
        let url = URL(string: "https://api.example.com/v1/api?default=true")!

        let config = ServerConfiguration(url: url, authToken: "token")

        #expect(config.url == url)
        #expect(config.url.path == "/v1/api")
        #expect(config.url.query == "default=true")
    }

}
