//
//  LocalizedErrorConformanceTests.swift
//  RagnarNetworking
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("LocalizedError Conformance Tests", .timeLimit(.minutes(1)))
struct LocalizedErrorConformanceTests {

    // MARK: - RequestError

    static let requestErrorCases: [RequestError] = [
        .configuration,
        .authentication,
        .componentsURL,
        .encoding(underlying: ErrorSnapshot(typeName: "TestError", description: "desc", localizedDescription: "desc")),
        .invalidRequest(description: "bad parameters"),
    ]

    @Test("RequestError produces a non-empty, non-default errorDescription", arguments: requestErrorCases)
    func testRequestErrorDescription(_ error: RequestError) {
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description?.isEmpty == false)
        #expect(description?.contains("RequestError") == false)
        #expect(description?.contains("error 1") == false)
    }

    // MARK: - InterfaceDecodingError

    static let interfaceDecodingErrorCases: [InterfaceDecodingError] = [
        .missingString,
        .missingData,
        .jsonDecoder(
            DecodingDiagnostics(
                kind: .keyNotFound,
                codingPath: ["user", "email"],
                debugDescription: "No value associated with key email."
            )
        ),
        .custom(message: "custom failure"),
    ]

    @Test("InterfaceDecodingError produces a non-empty, non-default errorDescription", arguments: interfaceDecodingErrorCases)
    func testInterfaceDecodingErrorDescription(_ error: InterfaceDecodingError) {
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description?.isEmpty == false)
        #expect(description?.contains("InterfaceDecodingError") == false)
        #expect(description?.contains("error 1") == false)
    }

    @Test("InterfaceDecodingError.jsonDecoder includes the coding path")
    func testJSONDecoderErrorIncludesCodingPath() {
        let error = InterfaceDecodingError.jsonDecoder(
            DecodingDiagnostics(
                kind: .typeMismatch,
                codingPath: ["items", "0", "id"],
                debugDescription: "Expected to decode Int but found a string instead."
            )
        )

        #expect(error.errorDescription?.contains("items.0.id") == true)
    }

    // MARK: - SocketIOError

    static let socketIOErrorCases: [SocketIOError] = [
        .notConnected,
        .encodingFailed,
    ]

    @Test("SocketIOError produces a non-empty, non-default errorDescription", arguments: socketIOErrorCases)
    func testSocketIOErrorDescription(_ error: SocketIOError) {
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description?.isEmpty == false)
        #expect(description?.contains("SocketIOError") == false)
        #expect(description?.contains("error 1") == false)
    }

    // MARK: - Existing conformances unchanged

    @Test("ResponseError.errorDescription is unchanged")
    func testResponseErrorDescriptionUnchanged() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/test")!,
            statusCode: 418,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let snapshot = HTTPResponseSnapshot(response: response)
        let error = ResponseError.unknownResponseCase(ResponseBody(Data()), snapshot)

        #expect(error.errorDescription == "Received an unhandled HTTP status code (418).")
    }

    @Test("APIClientError.errorDescription is unchanged")
    func testAPIClientErrorDescriptionUnchanged() {
        let error = APIClientError.invalidated

        #expect(error.errorDescription == "The API client has been invalidated and can no longer send requests.")
    }

}
