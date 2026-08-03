//
//  CodingConfigurationTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-01.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("Coding Configuration Tests", .timeLimit(.minutes(1)))
struct CodingConfigurationTests {

    // MARK: - Fixtures

    struct Payload: Codable, Equatable, Sendable {
        let orderId: Int
        let placedAt: Date
    }

    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Snake-cased keys and ISO8601 dates, standing in for a client's configured rules.
    static let configuredDecoder = ResponseDecoder(
        keyDecodingStrategy: .convertFromSnakeCase,
        dateDecodingStrategy: .iso8601
    )

    static let configuredEncoder = RequestEncoder(
        keyEncodingStrategy: .convertToSnakeCase,
        dateEncodingStrategy: .iso8601
    )

    // MARK: - ResponseDecoder.modified

    @Test("modified overrides one strategy and keeps the rest of the configuration")
    func testDecoderModifiedPreservesBaseConfiguration() throws {
        let body = #"{"order_id": 7, "placed_at": 1700000000}"#.data(using: .utf8)!

        let decoded = try Self.configuredDecoder
            .modified { $0.dateDecodingStrategy = .secondsSince1970 }
            .decode(Payload.self, from: body)

        // convertFromSnakeCase survived: order_id still mapped to orderId.
        #expect(decoded == Payload(orderId: 7, placedAt: Self.epoch))
    }

    @Test("modified leaves the original configuration untouched")
    func testDecoderModifiedDoesNotMutateBase() throws {
        let epochBody = #"{"order_id": 7, "placed_at": 1700000000}"#.data(using: .utf8)!
        let isoBody = #"{"order_id": 7, "placed_at": "2023-11-14T22:13:20Z"}"#.data(using: .utf8)!

        _ = try Self.configuredDecoder
            .modified { $0.dateDecodingStrategy = .secondsSince1970 }
            .decode(Payload.self, from: epochBody)

        // The base still decodes ISO8601 and rejects the epoch form.
        #expect(try Self.configuredDecoder.decode(Payload.self, from: isoBody).placedAt == Self.epoch)
        #expect(throws: DecodingError.self) {
            try Self.configuredDecoder.decode(Payload.self, from: epochBody)
        }
    }

    @Test("modified composes, with the last applied strategy winning")
    func testDecoderModifiedComposes() throws {
        let body = #"{"order_id": 7, "placed_at": 1700000000}"#.data(using: .utf8)!

        let decoded = try Self.configuredDecoder
            .modified { $0.dateDecodingStrategy = .millisecondsSince1970 }
            .modified { $0.dateDecodingStrategy = .secondsSince1970 }
            .decode(Payload.self, from: body)

        #expect(decoded.placedAt == Self.epoch)
    }

    // MARK: - RequestEncoder.modified

    @Test("modified overrides one strategy and keeps the rest of the configuration")
    func testEncoderModifiedPreservesBaseConfiguration() throws {
        let data = try Self.configuredEncoder
            .modified { $0.dateEncodingStrategy = .secondsSince1970 }
            .encode(Payload(orderId: 7, placedAt: Self.epoch))

        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])

        // convertToSnakeCase survived.
        #expect(json["order_id"] as? Int == 7)
        #expect(json["placed_at"] as? Double == 1_700_000_000)
    }

    @Test("modified leaves the original configuration untouched")
    func testEncoderModifiedDoesNotMutateBase() throws {
        _ = try Self.configuredEncoder
            .modified { $0.dateEncodingStrategy = .secondsSince1970 }
            .encode(Payload(orderId: 7, placedAt: Self.epoch))

        let data = try Self.configuredEncoder.encode(Payload(orderId: 7, placedAt: Self.epoch))
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])

        #expect(json["placed_at"] as? String == "2023-11-14T22:13:20Z")
    }

    // MARK: - End to End

    /// A response type whose wire format differs from the rest of the API in one strategy.
    struct LegacyOrder: Decodable, Equatable, Sendable, InterfaceResponse {
        let orderId: Int
        let placedAt: Date

        static func decode(
            from data: Data,
            metadata: HTTPResponseSnapshot,
            using decoder: ResponseDecoder
        ) throws -> LegacyOrder {
            try decoder
                .modified { $0.dateDecodingStrategy = .secondsSince1970 }
                .decode(LegacyOrder.self, from: data)
        }
    }

    struct LegacyOrderInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/legacy/orders/1"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = LegacyOrder

        static let responseCases: ResponseMap = [.code(200, .decode)]
    }

    @Test("An InterfaceResponse overriding one strategy still receives the client's other rules")
    func testInterfaceResponseDerivesFromConfiguredDecoder() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/legacy/orders/1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try LegacyOrderInterface.handle(
            (data: #"{"order_id": 7, "placed_at": 1700000000}"#.data(using: .utf8)!, response: httpResponse),
            context: ResponseContext(responseDecoder: Self.configuredDecoder),
            defaultHandler: DefaultResponseHandler()
        )

        #expect(result == LegacyOrder(orderId: 7, placedAt: Self.epoch))
    }

    /// A request body whose wire format differs from the rest of the API in one strategy.
    struct LegacyOrderDraft: Encodable, Sendable, RequestBody {
        let orderId: Int
        let placedAt: Date

        func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody {
            EncodedBody(
                data: try encoder
                    .modified { $0.dateEncodingStrategy = .secondsSince1970 }
                    .encode(self),
                contentType: "application/json"
            )
        }
    }

    @Test("A RequestBody overriding one strategy still receives the client's other rules")
    func testRequestBodyDerivesFromConfiguredEncoder() throws {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .post
            let path = "/legacy/orders"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: LegacyOrderDraft
            let authentication: AuthenticationScheme? = nil
        }

        let context = RequestContext(
            configuration: ServerConfiguration(
                url: URL(string: "https://api.example.com")!,
                requestEncoder: Self.configuredEncoder
            )
        )

        let request = try URLRequest(
            interfaceRequest: Request(
                body: LegacyOrderDraft(orderId: 7, placedAt: Self.epoch)
            ),
            context: context
        )

        let httpBody = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: httpBody)
        let json = try #require(object as? [String: Any])

        #expect(json["order_id"] as? Int == 7)
        #expect(json["placed_at"] as? Double == 1_700_000_000)
    }

}
