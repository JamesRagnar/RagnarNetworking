//
//  ResponseBodyTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("ResponseBody Tests", .timeLimit(.minutes(1)))
struct ResponseBodyTests {

    private struct Payload: Decodable, Equatable {
        let userId: Int
    }

    // MARK: - String Value

    @Test("stringValue returns the body as UTF-8")
    func testStringValue() {
        let body = ResponseBody("server exploded".data(using: .utf8)!)

        #expect(body.stringValue == "server exploded")
    }

    @Test("stringValue returns nil for bytes that are not valid UTF-8")
    func testStringValueInvalidUTF8() {
        let body = ResponseBody(Data([0xFF, 0xFE, 0xFD]))

        #expect(body.stringValue == nil)
    }

    // MARK: - Decoding

    @Test("decode(as:) uses the decoder the body carries")
    func testDecodeUsesCarriedDecoder() {
        let body = ResponseBody(
            #"{"user_id": 42}"#.data(using: .utf8)!,
            decoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
        )

        #expect(body.decode(as: Payload.self) == Payload(userId: 42))
    }

    @Test("decode(as:) returns nil for malformed JSON")
    func testDecodeMalformedJSON() {
        let body = ResponseBody("not json".data(using: .utf8)!)

        #expect(body.decode(as: Payload.self) == nil)
    }

}
