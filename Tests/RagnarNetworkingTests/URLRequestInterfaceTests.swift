//
//  URLRequestInterfaceTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("URLRequest+Interface Tests", .timeLimit(.minutes(1)))
struct URLRequestInterfaceTests {

    // MARK: - Test Fixtures

    struct BasicRequest: InterfaceRequest {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = nil
    }

    struct AuthenticatedRequest: InterfaceRequest {
        let method: RequestMethod = .post
        let path: String = "/api/users"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme?
    }

    struct ComplexRequest<BodyType: RequestBody>: InterfaceRequest {
        typealias Body = BodyType
        let method: RequestMethod = .put
        let path: String = "/api/update"
        let queryItems: [URLQueryItem]?
        let headers: [String: String]?
        let body: BodyType
        let authentication: AuthenticationScheme?
    }

    // MARK: - Basic Request Construction

    @Test("Constructs basic GET request")
    func testBasicGETRequest() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "/test")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        // URLComponents may add a trailing ? even with no query items
        #expect(request.url?.absoluteString == "https://api.example.com/test")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("Constructs request with different HTTP methods")
    func testDifferentHTTPMethods() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))

        let methods: [RequestMethod] = [.get, .post, .put, .delete, .patch, .head, .options]

        for method in methods {
            struct TestParams: InterfaceRequest {
                let method: RequestMethod
                let path = "/test"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            let params = TestParams(method: method)
            let request = try URLRequest(
                interfaceRequest: params,
                context: config
            )

            #expect(request.httpMethod == method.rawValue)
        }
    }

    // MARK: - Authentication

    @Test("Adds bearer token to headers")
    func testBearerAuthentication() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "secret-token")
        let params = AuthenticatedRequest(authentication: .bearer)

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test("Adds token to URL query parameters")
    func testURLAuthentication() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "url-token")
        let params = AuthenticatedRequest(authentication: .url)

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url?.query?.contains("token=url-token") == true)
    }

    @Test("Throws authentication error when bearer token is missing")
    func testMissingBearerToken() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url)) // No token
        let params = AuthenticatedRequest(authentication: .bearer)

        #expect(throws: RequestError.self) {
            try URLRequest(
                interfaceRequest: params,
                context: config
            )
        }
    }

    @Test("Throws authentication error when URL token is missing")
    func testMissingURLToken() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url)) // No token
        let params = AuthenticatedRequest(authentication: .url)

        #expect(throws: RequestError.self) {
            try URLRequest(
                interfaceRequest: params,
                context: config
            )
        }
    }

    @Test("No authentication added for .none type")
    func testNoAuthentication() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "should-not-be-used")
        let params = AuthenticatedRequest(authentication: .none)

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        // URLComponents may set query to empty string instead of nil
        let query = request.url?.query
        #expect(query == nil || query == "")
    }

    // MARK: - Query Request

    @Test("Adds query parameters to URL")
    func testQueryParameters() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<EmptyBody>(
            queryItems: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "limit", value: "10")],
            headers: nil,
            body: .init(),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("page=1"))
        #expect(urlString.contains("limit=10"))
    }

    @Test("Preserves query item order and duplicate keys")
    func testOrderedQueryItems() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<EmptyBody>(
            queryItems: [
                URLQueryItem(name: "sort", value: "title"),
                URLQueryItem(name: "filter", value: "new"),
                URLQueryItem(name: "filter", value: "featured")
            ],
            headers: nil,
            body: .init(),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems == params.queryItems)
    }

    @Test("Supports nil-valued query items")
    func testNilValuedQueryItems() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<EmptyBody>(
            queryItems: [URLQueryItem(name: "flag", value: nil)],
            headers: nil,
            body: .init(),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let item = components?.queryItems?.first(where: { $0.name == "flag" })
        #expect(item != nil)
        #expect(item?.value == nil)
    }

    @Test("Preserves existing query parameters from base URL")
    func testPreservesBaseURLQueryParameters() throws {
        let url = URL(string: "https://api.example.com?existing=value")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<EmptyBody>(
            queryItems: [URLQueryItem(name: "new", value: "param")],
            headers: nil,
            body: .init(),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("existing=value"))
        #expect(urlString.contains("new=param"))
    }

    @Test("Combines URL auth token with query parameters")
    func testURLAuthWithQueryParameters() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "auth-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: [URLQueryItem(name: "filter", value: "active")],
            headers: nil,
            body: .init(),
            authentication: .url
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("token=auth-token"))
        #expect(urlString.contains("filter=active"))
    }

    @Test("A token query item in the request collides with URL authentication")
    func testURLAuthTokenConflict() {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "auth-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: [URLQueryItem(name: "token", value: "custom-token")],
            headers: nil,
            body: .init(),
            authentication: .url
        )

        #expect {
            _ = try URLRequest(interfaceRequest: params, context: config)
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .url && name.caseInsensitiveCompare("token") == .orderedSame
        }
    }

    @Test("A token query item in the base URL collides with URL authentication")
    func testURLAuthTokenOverridesBaseURLToken() {
        let url = URL(string: "https://api.example.com?token=base-token")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "auth-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: nil,
            headers: nil,
            body: .init(),
            authentication: .url
        )

        #expect {
            _ = try URLRequest(interfaceRequest: params, context: config)
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .url && name.caseInsensitiveCompare("token") == .orderedSame
        }
    }

    @Test("URL authentication collides case-insensitively")
    func testURLAuthTokenOverridesTokenCaseInsensitive() {
        let url = URL(string: "https://api.example.com?TOKEN=base-token")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "auth-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: [URLQueryItem(name: "Token", value: "custom-token")],
            headers: nil,
            body: .init(),
            authentication: .url
        )

        #expect {
            _ = try URLRequest(interfaceRequest: params, context: config)
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .url && name.caseInsensitiveCompare("token") == .orderedSame
        }
    }

    // MARK: - Headers

    @Test("Sets default Content-Type header for JSON body")
    func testDefaultContentTypeHeaderForJSON() throws {
        struct TestPayload: RequestBody, Encodable, Sendable {
            let name: String
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<TestPayload>(
            queryItems: nil,
            headers: nil,
            body: TestPayload(name: "sample"),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Adds custom headers")
    func testCustomHeaders() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<EmptyBody>(
            queryItems: nil,
            headers: ["X-Custom-Header": "custom-value", "Accept-Language": "en-US"],
            body: .init(),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "custom-value")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US")
    }

    @Test("Content-Type with charset matches base media type")
    func testContentTypeCharsetNormalization() throws {
        struct Body: RequestBody, Encodable, Sendable {
            let value: String
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<Body>(
            queryItems: nil,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: Body(value: "test"),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
    }

    @Test("Content-Type mismatch with different media type fails")
    func testContentTypeMismatchFails() throws {
        struct XmlBody: RequestBody, Sendable {
            func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody {
                EncodedBody(data: Data("<xml/>".utf8), contentType: "application/xml")
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<XmlBody>(
            queryItems: nil,
            headers: ["Content-Type": "application/json"],
            body: XmlBody(),
            authentication: .none
        )

        #expect(throws: RequestError.self) {
            _ = try URLRequest(
                interfaceRequest: params,
                context: config
            )
        }
    }

    @Test("Combines bearer auth with custom headers")
    func testBearerAuthWithCustomHeaders() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "bearer-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: nil,
            headers: ["X-Request-ID": "12345"],
            body: .init(),
            authentication: .bearer
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer bearer-token")
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "12345")
    }

    @Test("A caller-supplied Authorization header collides with bearer auth")
    func testAuthorizationHeaderOverridesBearerToken() {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "auth-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: nil,
            headers: ["Authorization": "Custom token"],
            body: .init(),
            authentication: .bearer
        )

        #expect {
            _ = try URLRequest(interfaceRequest: params, context: config)
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .bearer && name.caseInsensitiveCompare("Authorization") == .orderedSame
        }
    }

    @Test("An Authorization collision is detected case-insensitively")
    func testAuthorizationHeaderOverrideIsCaseInsensitive() {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "auth-token")
        let params = ComplexRequest<EmptyBody>(
            queryItems: nil,
            headers: ["authorization": "Custom token"],
            body: .init(),
            authentication: .bearer
        )

        #expect {
            _ = try URLRequest(interfaceRequest: params, context: config)
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .bearer && name.caseInsensitiveCompare("Authorization") == .orderedSame
        }
    }

    // MARK: - Body

    @Test("Request with EmptyBody has no body or Content-Type")
    func testEmptyBodyRequest() throws {
        struct EmptyBodyParams: InterfaceRequest {
            let method: RequestMethod = .get
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let request = try URLRequest(
            interfaceRequest: EmptyBodyParams(),
            context: config
        )

        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("Adds request body")
    func testRequestBody() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let bodyData = "test body".data(using: .utf8)!
        let params = ComplexRequest<BinaryBody>(
            queryItems: nil,
            headers: nil,
            body: BinaryBody(data: bodyData, contentType: "application/octet-stream"),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.httpBody == bodyData)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    }

    @Test("Handles JSON body data")
    func testJSONBody() throws {
        struct TestPayload: RequestBody, Codable, Sendable {
            let name: String
            let value: Int
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let payload = TestPayload(name: "test", value: 42)
        let params = ComplexRequest<TestPayload>(
            queryItems: nil,
            headers: nil,
            body: payload,
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        // Verify we can decode it back
        #expect(request.httpBody != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let decoded = try JSONDecoder().decode(TestPayload.self, from: request.httpBody!)
        #expect(decoded.name == "test")
        #expect(decoded.value == 42)
    }

    @Test("Request body with custom content type")
    func testCustomContentType() throws {
        struct CustomBody: RequestBody, Sendable {
            let data: String

            func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody {
                EncodedBody(
                    data: Data(data.utf8),
                    contentType: "application/xml"
                )
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<CustomBody>(
            queryItems: nil,
            headers: nil,
            body: CustomBody(data: "<xml/>"),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8) == "<xml/>")
    }

    @Test("Request body with binary data")
    func testBinaryDataBody() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let binaryBody = BinaryBody(data: imageData, contentType: "image/jpeg")
        let params = ComplexRequest<BinaryBody>(
            queryItems: nil,
            headers: nil,
            body: binaryBody,
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.httpBody == imageData)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
    }

    @Test("Handles text body")
    func testTextBody() throws {
        struct TextBody: RequestBody, Sendable {
            let text: String

            func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody {
                EncodedBody(
                    data: Data(text.utf8),
                    contentType: "text/plain; charset=utf-8"
                )
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<TextBody>(
            queryItems: nil,
            headers: nil,
            body: TextBody(text: "hello"),
            authentication: .none
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8)
        #expect(bodyString == "hello")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
    }

    @Test("Throws encoding error for body encoding failure")
    func testBodyEncodingError() throws {
        struct FailingBody: RequestBody, Sendable {
            struct TestError: LocalizedError, Sendable {
                var errorDescription: String? {
                    "Intentional encoding failure"
                }
            }

            func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody {
                throw TestError()
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ComplexRequest<FailingBody>(
            queryItems: nil,
            headers: nil,
            body: FailingBody(),
            authentication: .none
        )

        do {
            _ = try URLRequest(
                interfaceRequest: params,
                context: config
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .encoding(let underlying) = error {
                #expect(underlying.description.isEmpty == false)
                #expect(underlying.typeName.contains("TestError"))
                #expect(underlying.localizedDescription == "Intentional encoding failure")
            } else {
                #expect(Bool(false), "Expected .encoding error case")
            }
        }
    }

    @Test("Request body uses configured encoder strategies")
    func testEncoderConfiguration() throws {
        struct EncoderBody: RequestBody, Encodable, Sendable {
            let userName: String
            let createdAt: Date
        }

        struct TestParams: InterfaceRequest {
            typealias Body = EncoderBody
            let method: RequestMethod = .post
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EncoderBody
            let authentication: AuthenticationScheme? = nil
        }

        let config = RequestContext(
            configuration: ServerConfiguration(
                url: URL(string: "https://test.example.com")!,
                requestEncoder: RequestEncoder(
                    keyEncodingStrategy: .convertToSnakeCase,
                    dateEncodingStrategy: .iso8601
                )
            )
        )

        let date = ISO8601DateFormatter().date(from: "2026-02-03T12:00:00Z")!
        let params = TestParams(body: EncoderBody(userName: "test", createdAt: date))
        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]

        #expect(json["user_name"] as? String == "test")
        #expect(json["userName"] == nil)
        #expect(json["created_at"] as? String == "2026-02-03T12:00:00Z")
    }

    @Test("ArrayBody encodes top-level array")
    func testArrayBody() throws {
        struct TestParams: InterfaceRequest {
            typealias Body = ArrayBody<Int>
            let method: RequestMethod = .post
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: ArrayBody<Int>
            let authentication: AuthenticationScheme? = nil
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestParams(body: ArrayBody([1, 2, 3]))

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let decoded = try JSONDecoder().decode([Int].self, from: request.httpBody!)
        #expect(decoded == [1, 2, 3])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("EncodableBody wraps existing Encodable type")
    func testEncodableBody() throws {
        struct LegacyPayload: Codable, Equatable, Sendable {
            let id: Int
            let name: String
        }

        struct TestParams: InterfaceRequest {
            typealias Body = EncodableBody<LegacyPayload>
            let method: RequestMethod = .post
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EncodableBody<LegacyPayload>
            let authentication: AuthenticationScheme? = nil
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let payload = LegacyPayload(id: 42, name: "test")
        let params = TestParams(body: EncodableBody(payload))

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let decoded = try JSONDecoder().decode(LegacyPayload.self, from: request.httpBody!)
        #expect(decoded == payload)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Nullable encodes explicit null")
    func testNullableEncodesNull() throws {
        struct PayloadWithNullable: RequestBody, Encodable, Sendable {
            let nickname: Nullable<String>?
        }

        struct TestParams: InterfaceRequest {
            typealias Body = PayloadWithNullable
            let method: RequestMethod = .post
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: PayloadWithNullable
            let authentication: AuthenticationScheme? = nil
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestParams(body: PayloadWithNullable(nickname: .null))

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(json.keys.contains("nickname"))
        #expect(json["nickname"] is NSNull)
    }

    @Test("Nullable encodes value")
    func testNullableEncodesValue() throws {
        struct PayloadWithNullable: RequestBody, Encodable, Sendable {
            let nickname: Nullable<String>?
        }

        struct TestParams: InterfaceRequest {
            typealias Body = PayloadWithNullable
            let method: RequestMethod = .post
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: PayloadWithNullable
            let authentication: AuthenticationScheme? = nil
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestParams(body: PayloadWithNullable(nickname: .value("Bob")))

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(json["nickname"] as? String == "Bob")
    }

    @Test("Nullable omits field when property is nil")
    func testNullableOmitsWhenNil() throws {
        struct PayloadWithNullable: RequestBody, Encodable, Sendable {
            let nickname: Nullable<String>?
        }

        struct TestParams: InterfaceRequest {
            typealias Body = PayloadWithNullable
            let method: RequestMethod = .post
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: PayloadWithNullable
            let authentication: AuthenticationScheme? = nil
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestParams(body: PayloadWithNullable(nickname: nil))

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(!json.keys.contains("nickname"))
    }

    // MARK: - Path Handling

    @Test("Constructs path correctly")
    func testPathConstruction() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "/api/v1/users/123")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url?.path == "/api/v1/users/123")
    }

    @Test("Handles path with leading slash")
    func testPathWithLeadingSlash() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "/api/users")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url?.path == "/api/users")
        #expect(request.url?.absoluteString.contains("api/users") == true)
    }

    @Test("Appends path to base URL path")
    func testAppendsPathToBaseURLPath() throws {
        let url = URL(string: "https://api.example.com/v1")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "/users")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url?.path == "/v1/users")
    }

    @Test("Appends path to base URL path with trailing slash")
    func testAppendsPathToBaseURLPathWithTrailingSlash() throws {
        let url = URL(string: "https://api.example.com/v1/")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "/users")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url?.path == "/v1/users")
    }

    @Test("Normalizes missing leading slash in path")
    func testNormalizesMissingLeadingSlash() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "users")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url?.path == "/users")
    }

    // MARK: - Error Cases

    @Test("Valid configuration builds request successfully")
    func testValidURLConfiguration() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = BasicRequest(path: "/test")

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
        )

        #expect(request.url != nil)
    }

    // MARK: - Interface-typed initializer

    @Test("Interface-typed init produces equivalent request to InterfaceRequest init")
    func testInterfaceTypedInit() throws {
        struct SimpleInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path: String = "/api/check"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }
            struct Response: Decodable, Sendable, InterfaceResponse {}
            static var responseCases: ResponseMap { [.code(200, .decode)] }
        }

        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url))
        let params = SimpleInterface.Request()

        let viaInterface = try URLRequest(SimpleInterface.self, params, context: config)
        let viaParams = try URLRequest(interfaceRequest: params, context: config)

        #expect(viaInterface.url == viaParams.url)
        #expect(viaInterface.httpMethod == viaParams.httpMethod)
    }

    // MARK: - RequestEncoder

    @Test("RequestEncoder with custom factory uses the provided encoder")
    func testCustomEncoderFactory() throws {
        let encoder = RequestEncoder(makeJSONEncoder: {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            return e
        })

        struct Payload: Encodable { let myKey: String }
        let produced = encoder.makeJSONEncoder()
        let data = try produced.encode(Payload(myKey: "value"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["my_key"] as? String == "value")
        #expect(json["myKey"] == nil)
    }

    // MARK: - Integration Tests

    @Test("Constructs complete complex request")
    func testComplexRequest() throws {
        let url = URL(string: "https://api.example.com")!
        let config = RequestContext(configuration: ServerConfiguration(url: url), credential: "complex-token")
        let bodyData = "{\"test\":\"data\"}".data(using: .utf8)!
        let params = ComplexRequest<BinaryBody>(
            queryItems: [URLQueryItem(name: "filter", value: "active"), URLQueryItem(name: "sort", value: "name")],
            headers: ["X-API-Version": "2.0", "X-Client-ID": "ios-app"],
            body: BinaryBody(data: bodyData, contentType: "application/octet-stream"),
            authentication: .bearer
        )

        let request = try URLRequest(
            interfaceRequest: params,
            context: config
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

    // MARK: - Custom RequestBuilder Composition

    /// A custom builder that reuses `URLRequestBuilder`'s steps but substitutes its own
    /// content-type handling.
    struct ContentTypeOverridingBuilder: RequestBuilder {
        func buildRequest<Request: InterfaceRequest>(
            _ interfaceRequest: Request,
            context: RequestContext
        ) throws(RequestError) -> URLRequest {
            let base = URLRequestBuilder()
            var components = try base.makeComponents(context: context)
            base.applyPath(interfaceRequest.path, to: &components)
            base.applyQueryItems(interfaceRequest.queryItems, to: &components)

            var request = base.makeRequest(url: try base.makeURL(from: components))
            base.applyMethod(interfaceRequest.method, to: &request)
            base.applyHeaders(context.resolvedHeaders(for: interfaceRequest), to: &request)

            var headers = request.allHTTPHeaderFields ?? [:]
            headers["Content-Type"] = "application/vnd.custom+json"
            headers["X-Override-Ran"] = "yes"
            request.allHTTPHeaderFields = headers

            return request
        }
    }

    @Test("A custom RequestBuilder composing URLRequestBuilder's steps substitutes its own content type")
    func customBuilderComposesDefaultSteps() throws {
        struct Body: RequestBody, Encodable { let a: Int }
        struct Request: InterfaceRequest {
            let method: RequestMethod = .post
            let path: String = "/x"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: Body = Body(a: 1)
            let authentication: AuthenticationScheme? = nil
        }

        let request = try ContentTypeOverridingBuilder().buildRequest(
            Request(),
            context: RequestContext(
                configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!)
            )
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.custom+json")
        #expect(request.value(forHTTPHeaderField: "X-Override-Ran") == "yes")
    }

    /// Reassembles the default pipeline out of `URLRequestBuilder`'s public steps, changing
    /// nothing. If delegation is a real substitute for the default builder, the two must agree
    /// byte for byte.
    struct DelegatingBuilder: RequestBuilder {
        func buildRequest<Request: InterfaceRequest>(
            _ interfaceRequest: Request,
            context: RequestContext
        ) throws(RequestError) -> URLRequest {
            let base = URLRequestBuilder()

            var components = try base.makeComponents(context: context)
            base.applyPath(interfaceRequest.path, to: &components)
            base.applyQueryItems(interfaceRequest.queryItems, to: &components)

            return try base.finishRequest(
                interfaceRequest,
                components: components,
                context: context
            )
        }
    }

    @Test("A builder delegating to URLRequestBuilder's steps matches the default pipeline byte for byte")
    func delegatingBuilderMatchesDefaultPipeline() throws {
        struct Body: RequestBody, Encodable { let a: Int }
        struct Request: InterfaceRequest {
            let method: RequestMethod = .post
            let path: String = "/users/1"
            let queryItems: [URLQueryItem]? = [URLQueryItem(name: "sort", value: "name")]
            let headers: [String: String]? = ["X-Request-Header": "request"]
            let body: Body = Body(a: 1)
            let authentication: AuthenticationScheme? = .bearer
        }

        let context = RequestContext(
            configuration: ServerConfiguration(
                url: URL(string: "https://api.example.com/v1")!,
                defaultHeaders: ["X-App-Version": "1.0"]
            ),
            credential: "abc123"
        )

        let expected = try URLRequest(interfaceRequest: Request(), context: context)

        let delegated = try URLRequest(
            interfaceRequest: Request(),
            context: RequestContext(
                configuration: ServerConfiguration(
                    url: URL(string: "https://api.example.com/v1")!,
                    defaultHeaders: ["X-App-Version": "1.0"],
                    builder: DelegatingBuilder()
                ),
                credential: "abc123"
            )
        )

        #expect(delegated.url == expected.url)
        #expect(delegated.httpMethod == expected.httpMethod)
        #expect(delegated.allHTTPHeaderFields == expected.allHTTPHeaderFields)
        #expect(delegated.httpBody == expected.httpBody)
    }

    @Test("URLRequestBuilder's mediaTypesMatch is reusable on its own")
    func mediaTypesMatchIsReusable() {
        let builder = URLRequestBuilder()

        #expect(builder.mediaTypesMatch("application/json", "application/json; charset=utf-8"))
        #expect(builder.mediaTypesMatch("APPLICATION/JSON", "application/json"))
        #expect(!builder.mediaTypesMatch("text/plain", "application/json"))
    }

    // MARK: - Default Headers

    @Test("Default headers are applied to a built request")
    func testDefaultHeadersApplied() throws {
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: URL(string: "https://api.example.com")!,
                defaultHeaders: ["X-App-Version": "1.0"]
            )
        )

        let request = try URLRequest(
            interfaceRequest: BasicRequest(path: "/test"),
            context: context
        )

        #expect(request.value(forHTTPHeaderField: "X-App-Version") == "1.0")
    }

    @Test("A request header overrides a default header of the same name, case-insensitively")
    func testRequestHeaderOverridesDefaultCaseInsensitively() throws {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path: String = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = ["Accept-Language": "fr-FR"]
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        let context = RequestContext(
            configuration: ServerConfiguration(
                url: URL(string: "https://api.example.com")!,
                defaultHeaders: ["accept-language": "en-US"]
            )
        )

        let request = try URLRequest(
            interfaceRequest: Request(),
            context: context
        )

        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "fr-FR")
        #expect(request.allHTTPHeaderFields?.count == 1)
    }

}
