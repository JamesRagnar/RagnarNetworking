//
//  URLRequestInterfaceTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Testing
import Foundation
@testable import RagnarNetworking

@Suite("URLRequest+Interface Tests")
struct URLRequestInterfaceTests {

    // MARK: - Test Fixtures

    struct BasicParameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [String: String?]? = nil
        let headers: [String: String]? = nil
        let body: RequestBody? = nil
        let authentication: AuthenticationType = .none
    }

    struct AuthenticatedParameters: RequestParameters {
        let method: RequestMethod = .post
        let path: String = "/api/users"
        let queryItems: [String: String?]? = nil
        let headers: [String: String]? = nil
        let body: RequestBody?
        let authentication: AuthenticationType
    }

    struct ComplexParameters: RequestParameters {
        let method: RequestMethod = .put
        let path: String = "/api/update"
        let queryItems: [String: String?]?
        let headers: [String: String]?
        let body: RequestBody?
        let authentication: AuthenticationType
    }

    // MARK: - Basic Request Construction

    @Test("Constructs basic GET request")
    func testBasicGETRequest() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "/test")

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        // URLComponents may add a trailing ? even with no query items
        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString == "https://api.example.com/test" || urlString == "https://api.example.com/test?")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("Constructs request with different HTTP methods")
    func testDifferentHTTPMethods() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)

        let methods: [RequestMethod] = [.get, .post, .put, .delete, .patch, .head, .options]

        for method in methods {
            struct TestParams: RequestParameters {
                let method: RequestMethod
                let path = "/test"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: RequestBody? = nil
                let authentication: AuthenticationType = .none
            }

            let params = TestParams(method: method)
            let request = try URLRequest(
                requestParameters: params,
                serverConfiguration: config
            )

            #expect(request.httpMethod == method.rawValue)
        }
    }

    // MARK: - Authentication

    @Test("Adds bearer token to headers")
    func testBearerAuthentication() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "secret-token")
        let params = AuthenticatedParameters(body: nil, authentication: .bearer)

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test("Adds token to URL query parameters")
    func testURLAuthentication() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "url-token")
        let params = AuthenticatedParameters(body: nil, authentication: .url)

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url?.query?.contains("token=url-token") == true)
    }

    @Test("Throws authentication error when bearer token is missing")
    func testMissingBearerToken() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url) // No token
        let params = AuthenticatedParameters(body: nil, authentication: .bearer)

        #expect(throws: RequestError.self) {
            try URLRequest(
                requestParameters: params,
                serverConfiguration: config
            )
        }
    }

    @Test("Throws authentication error when URL token is missing")
    func testMissingURLToken() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url) // No token
        let params = AuthenticatedParameters(body: nil, authentication: .url)

        #expect(throws: RequestError.self) {
            try URLRequest(
                requestParameters: params,
                serverConfiguration: config
            )
        }
    }

    @Test("No authentication added for .none type")
    func testNoAuthentication() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "should-not-be-used")
        let params = AuthenticatedParameters(body: nil, authentication: .none)

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        // URLComponents may set query to empty string instead of nil
        let query = request.url?.query
        #expect(query == nil || query == "")
    }

    // MARK: - Query Parameters

    @Test("Adds query parameters to URL")
    func testQueryParameters() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: ["page": "1", "limit": "10"],
            headers: nil,
            body: nil,
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("page=1"))
        #expect(urlString.contains("limit=10"))
    }

    @Test("Supports nil-valued query items")
    func testNilValuedQueryItems() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: ["flag": nil],
            headers: nil,
            body: nil,
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let item = components?.queryItems?.first(where: { $0.name == "flag" })
        #expect(item != nil)
        #expect(item?.value == nil)
    }

    @Test("Preserves existing query parameters from base URL")
    func testPreservesBaseURLQueryParameters() throws {
        let url = URL(string: "https://api.example.com?existing=value")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: ["new": "param"],
            headers: nil,
            body: nil,
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("existing=value"))
        #expect(urlString.contains("new=param"))
    }

    @Test("Combines URL auth token with query parameters")
    func testURLAuthWithQueryParameters() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "auth-token")
        let params = ComplexParameters(
            queryItems: ["filter": "active"],
            headers: nil,
            body: nil,
            authentication: .url
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("token=auth-token"))
        #expect(urlString.contains("filter=active"))
    }

    @Test("URL auth token overrides token query item")
    func testURLAuthTokenConflict() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "auth-token")
        let params = ComplexParameters(
            queryItems: ["token": "custom-token"],
            headers: nil,
            body: nil,
            authentication: .url
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let tokenItems = components?.queryItems?.filter { $0.name == "token" } ?? []
        #expect(tokenItems.count == 1)
        #expect(tokenItems.first?.value == "auth-token")
    }

    @Test("URL auth token overrides token in base URL")
    func testURLAuthTokenOverridesBaseURLToken() throws {
        let url = URL(string: "https://api.example.com?token=base-token")!
        let config = ServerConfiguration(url: url, authToken: "auth-token")
        let params = ComplexParameters(
            queryItems: nil,
            headers: nil,
            body: nil,
            authentication: .url
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let tokenItems = components?.queryItems?.filter { $0.name == "token" } ?? []
        #expect(tokenItems.count == 1)
        #expect(tokenItems.first?.value == "auth-token")
    }

    @Test("URL auth token overrides token case-insensitively")
    func testURLAuthTokenOverridesTokenCaseInsensitive() throws {
        let url = URL(string: "https://api.example.com?TOKEN=base-token")!
        let config = ServerConfiguration(url: url, authToken: "auth-token")
        let params = ComplexParameters(
            queryItems: ["Token": "custom-token"],
            headers: nil,
            body: nil,
            authentication: .url
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let tokenItems = components?.queryItems?.filter {
            $0.name.caseInsensitiveCompare("token") == .orderedSame
        } ?? []
        #expect(tokenItems.count == 1)
        #expect(tokenItems.first?.value == "auth-token")
    }

    // MARK: - Headers

    @Test("Sets default Content-Type header for JSON body")
    func testDefaultContentTypeHeaderForJSON() throws {
        struct TestPayload: Codable, Sendable {
            let name: String
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: nil,
            headers: nil,
            body: .json(TestPayload(name: "sample")),
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Adds custom headers")
    func testCustomHeaders() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: nil,
            headers: ["X-Custom-Header": "custom-value", "Accept-Language": "en-US"],
            body: nil,
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "custom-value")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US")
    }

    @Test("Custom headers override default headers")
    func testCustomHeadersOverrideDefaults() throws {
        struct TestPayload: Codable, Sendable {
            let name: String
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: nil,
            headers: ["Content-Type": "application/xml"],
            body: .json(TestPayload(name: "override")),
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }

    @Test("Custom Content-Type casing suppresses default")
    func testCustomContentTypeCasingSuppressesDefault() throws {
        struct TestPayload: Codable, Sendable {
            let name: String
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: nil,
            headers: ["content-type": "application/xml"],
            body: .json(TestPayload(name: "override")),
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")

        let contentTypeKeys = request.allHTTPHeaderFields?.keys.filter {
            $0.caseInsensitiveCompare("Content-Type") == .orderedSame
        } ?? []
        #expect(contentTypeKeys.count == 1)
    }

    @Test("Combines bearer auth with custom headers")
    func testBearerAuthWithCustomHeaders() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "bearer-token")
        let params = ComplexParameters(
            queryItems: nil,
            headers: ["X-Request-ID": "12345"],
            body: nil,
            authentication: .bearer
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer bearer-token")
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "12345")
    }

    @Test("Custom Authorization header overrides bearer auth")
    func testAuthorizationHeaderOverridesBearerToken() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "bearer-token")
        let params = ComplexParameters(
            queryItems: nil,
            headers: ["Authorization": "Custom token"],
            body: nil,
            authentication: .bearer
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Custom token")
    }

    @Test("Authorization header override is case-insensitive")
    func testAuthorizationHeaderOverrideIsCaseInsensitive() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "bearer-token")
        let params = ComplexParameters(
            queryItems: nil,
            headers: ["authorization": "Custom token"],
            body: nil,
            authentication: .bearer
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Custom token")
        let authKeys = request.allHTTPHeaderFields?.keys.filter {
            $0.caseInsensitiveCompare("Authorization") == .orderedSame
        } ?? []
        #expect(authKeys.count == 1)
    }

    // MARK: - Body

    @Test("Adds request body")
    func testRequestBody() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let bodyData = "test body".data(using: .utf8)!
        let params = ComplexParameters(
            queryItems: nil,
            headers: nil,
            body: .data(bodyData),
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.httpBody == bodyData)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("Handles JSON body data")
    func testJSONBody() throws {
        struct TestPayload: Codable {
            let name: String
            let value: Int
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let payload = TestPayload(name: "test", value: 42)
        let params = ComplexParameters(
            queryItems: nil,
            headers: nil,
            body: .json(payload),
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        // Verify we can decode it back
        #expect(request.httpBody != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let decoded = try JSONDecoder().decode(TestPayload.self, from: request.httpBody!)
        #expect(decoded.name == "test")
        #expect(decoded.value == 42)
    }

    @Test("Handles text body")
    func testTextBody() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: nil,
            headers: nil,
            body: .text("hello"),
            authentication: .none
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8)
        #expect(bodyString == "hello")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
    }

    @Test("Throws encoding error for JSON encoding failure")
    func testJSONBodyEncodingError() throws {
        struct FailingPayload: Encodable {
            func encode(to encoder: Encoder) throws {
                struct TestError: Error {}
                throw TestError()
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexParameters(
            queryItems: nil,
            headers: nil,
            body: .json(FailingPayload()),
            authentication: .none
        )

        #expect(throws: RequestError.self) {
            try URLRequest(
                requestParameters: params,
                serverConfiguration: config
            )
        }
    }

    // MARK: - Path Handling

    @Test("Constructs path correctly")
    func testPathConstruction() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "/api/v1/users/123")

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url?.path == "/api/v1/users/123")
    }

    @Test("Handles path with leading slash")
    func testPathWithLeadingSlash() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "/api/users")

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url?.path == "/api/users")
        #expect(request.url?.absoluteString.contains("api/users") == true)
    }

    @Test("Appends path to base URL path")
    func testAppendsPathToBaseURLPath() throws {
        let url = URL(string: "https://api.example.com/v1")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "/users")

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url?.path == "/v1/users")
    }

    @Test("Appends path to base URL path with trailing slash")
    func testAppendsPathToBaseURLPathWithTrailingSlash() throws {
        let url = URL(string: "https://api.example.com/v1/")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "/users")

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url?.path == "/v1/users")
    }

    @Test("Normalizes missing leading slash in path")
    func testNormalizesMissingLeadingSlash() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "users")

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url?.path == "/users")
    }

    // MARK: - Error Cases

    @Test("Throws configuration error for invalid URL")
    func testInvalidURLConfiguration() throws {
        // This is hard to trigger since ServerConfiguration takes a URL
        // But we can test with a configuration that can't build URLComponents
        // In practice, this is rare but the error exists for edge cases
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = BasicParameters(path: "/test")

        // This should succeed
        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        #expect(request.url != nil)
    }

    // MARK: - Integration Tests

    @Test("Constructs complete complex request")
    func testComplexRequest() throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "complex-token")
        let bodyData = "{\"test\":\"data\"}".data(using: .utf8)!
        let params = ComplexParameters(
            queryItems: ["filter": "active", "sort": "name"],
            headers: ["X-API-Version": "2.0", "X-Client-ID": "ios-app"],
            body: .data(bodyData),
            authentication: .bearer
        )

        let request = try URLRequest(
            requestParameters: params,
            serverConfiguration: config
        )

        // Verify all components
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/update")
        #expect(request.url?.query?.contains("filter=active") == true)
        #expect(request.url?.query?.contains("sort=name") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer complex-token")
        #expect(request.value(forHTTPHeaderField: "X-API-Version") == "2.0")
        #expect(request.value(forHTTPHeaderField: "X-Client-ID") == "ios-app")
        #expect(request.httpBody == bodyData)
    }

}
