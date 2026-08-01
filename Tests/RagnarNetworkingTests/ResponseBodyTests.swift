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

    // MARK: - Storage

    @Test("Stores the raw bytes it was created with")
    func testStoresData() {
        let data = #"{"userId": 1}"#.data(using: .utf8)!

        #expect(ResponseBody(data).data == data)
    }

    @Test("Defaults to a plain decoder when none is supplied")
    func testDefaultDecoderIsPlain() {
        let body = ResponseBody(#"{"userId": 1}"#.data(using: .utf8)!)

        #expect(body.decode(as: Payload.self) == Payload(userId: 1))
        #expect(ResponseBody(#"{"user_id": 1}"#.data(using: .utf8)!).decode(as: Payload.self) == nil)
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

    @Test("stringValue is empty for an empty body")
    func testStringValueEmptyBody() {
        #expect(ResponseBody(Data()).stringValue == "")
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

    @Test("decode(as:) returns nil for a mismatched type")
    func testDecodeMismatchedType() {
        struct Other: Decodable { let missing: String }

        let body = ResponseBody(#"{"userId": 1}"#.data(using: .utf8)!)

        #expect(body.decode(as: Other.self) == nil)
    }

    @Test("decode(as:) returns nil for an empty body")
    func testDecodeEmptyBody() {
        #expect(ResponseBody(Data()).decode(as: Payload.self) == nil)
    }

    // MARK: - Sendable

    @Test("Is Sendable")
    func testSendableConformance() {
        let _: any Sendable = ResponseBody(Data())
    }

}
