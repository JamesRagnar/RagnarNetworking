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

    static let requestErrorCases: [(RequestError, String)] = [
        (.configuration, "The server configuration could not be parsed or is malformed."),
        (.componentsURL, "The request URL could not be assembled from its components."),
        (
            .encoding(
                underlying: ErrorSnapshot(typeName: "TestError", description: "desc", localizedDescription: "desc")
            ),
            "The request body could not be encoded: desc"
        ),
        (.invalidRequest(description: "bad parameters"), "The request could not be constructed: bad parameters"),
        (.unregisteredScheme(.bearer), "No authenticator is registered for the 'bearer' authentication scheme."),
        (
            .missingCredential(.bearer),
            "The 'bearer' authentication scheme requires a credential, but none was provided."
        ),
        (
            .credentialCollision(scheme: .bearer, name: "Authorization"),
            "The 'bearer' authentication scheme writes 'Authorization', which this request already carries. Remove one of them."
        ),
        (
            .undeclaredQueryItemName(scheme: .url, name: "secret"),
            "The authenticator for the 'url' scheme wrote the query item 'secret' without declaring it in "
                + "redactedQueryItemNames, so it would leak into captured errors."
        ),
        (
            .authenticatorAppliedNothing(.bearer),
            "The authenticator for the 'bearer' scheme applied no credential, so the request would have been sent "
                + "unauthenticated."
        )
    ]

    @Test("RequestError descriptions are stable", arguments: requestErrorCases)
    func testRequestErrorDescription(_ error: RequestError, expected: String) {
        #expect(error.errorDescription == expected)
    }

    // MARK: - InterfaceDecodingError

    static let interfaceDecodingErrorCases: [(InterfaceDecodingError, String)] = [
        (.missingString, "The response was expected to be a UTF-8 string, but decoding failed."),
        (
            .jsonDecoder(
                DecodingDiagnostics(
                    kind: .keyNotFound,
                    codingPath: ["user", "email"],
                    debugDescription: "No value associated with key email."
                )
            ),
            "Failed to decode JSON at \"user.email\": No value associated with key email."
        ),
        (
            .jsonDecoder(
                DecodingDiagnostics(
                    kind: .dataCorrupted,
                    codingPath: [],
                    debugDescription: "The payload is not valid JSON."
                )
            ),
            "Failed to decode JSON: The payload is not valid JSON."
        ),
        (.custom(message: "custom failure"), "custom failure")
    ]

    @Test("InterfaceDecodingError descriptions are stable", arguments: interfaceDecodingErrorCases)
    func testInterfaceDecodingErrorDescription(_ error: InterfaceDecodingError, expected: String) {
        #expect(error.errorDescription == expected)
    }

    // MARK: - SocketIOError

    static let socketIOErrorCases: [(SocketIOError, String)] = [
        (.notConnected, "Cannot emit an event because the socket is not connected."),
        (.encodingFailed, "The event payload could not be serialized to a UTF-8 JSON string.")
    ]

    @Test("SocketIOError descriptions are stable", arguments: socketIOErrorCases)
    func testSocketIOErrorDescription(_ error: SocketIOError, expected: String) {
        #expect(error.errorDescription == expected)
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

    @Test(
        "APIClientError.errorDescription is unchanged",
        arguments: [
            (
                APIClientError.invalidated,
                "The API client has been invalidated and can no longer send requests."
            ),
            (
                APIClientError.noCredentialSource,
                "An authenticated request was challenged, but this client was created without token and refresh closures."
            )
        ]
    )
    func testAPIClientErrorDescriptionUnchanged(error: APIClientError, expected: String) {
        #expect(error.errorDescription == expected)
    }

    @Test("TransportError describes offline and timeout without URLError's generic wording")
    func testTransportErrorDescriptions() {
        #expect(
            TransportError.offline(URLError(.notConnectedToInternet)).errorDescription
                == "The Internet connection appears to be offline."
        )
        #expect(TransportError.timedOut(URLError(.timedOut)).errorDescription == "The request timed out.")
    }

    @Test("TransportError forwards the underlying error's description for the pass-through cases")
    func testTransportErrorForwardsUnderlyingDescription() {
        let urlError = URLError(.cannotFindHost)

        #expect(TransportError.url(urlError).errorDescription == urlError.localizedDescription)
        #expect(TransportError.other(urlError).errorDescription == urlError.localizedDescription)
    }

}
