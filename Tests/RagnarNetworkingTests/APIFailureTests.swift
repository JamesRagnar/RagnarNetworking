//
//  APIFailureTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Fixtures

private let testServerURL = URL(string: "https://api.example.com")!

private struct ValueResponse: Codable, Sendable, Equatable, InterfaceResponse {
    let value: String
}

private struct PlainInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/resource"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = nil
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

private struct BearerInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/secure"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

/// Declares no scheme, so no credential is ever applied, but opts into challenge retry. On a
/// client built without credential closures that is the only route to `.noCredentialSource`.
private struct CookieAuthInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/cookie"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = nil

        var refreshesOnChallenge: Bool { true }
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

/// Throws whatever it is handed, so a test can drive the transport classification directly.
private struct ThrowingTransport: Transport {
    let error: any Error

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw error
    }
}

private actor StatusTransport: Transport {
    private let statusCode: Int
    private(set) var callCount = 0

    init(statusCode: Int) {
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        let response = HTTPURLResponse(
            url: request.url ?? testServerURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}

private func client(
    transport: any Transport,
    token: @escaping @Sendable () async throws -> String? = { "tok" },
    refresh: @escaping @Sendable () async throws -> Void = {}
) -> APIClient {
    APIClient(
        configuration: ServerConfiguration(url: testServerURL),
        transport: transport,
        token: token,
        refresh: refresh
    )
}

// MARK: - Transport Classification

@Suite("APIFailure: transport classification", .timeLimit(.minutes(1)))
struct APIFailureTransportTests {

    @Test(
        "Offline URLError codes classify as .transport(.offline)",
        arguments: [
            URLError.Code.notConnectedToInternet,
            .networkConnectionLost,
            .dataNotAllowed,
            .internationalRoamingOff
        ]
    )
    func offlineCodesClassifyAsOffline(code: URLError.Code) async throws {
        let failure = await apiFailure {
            try await client(transport: ThrowingTransport(error: URLError(code)))
                .send(PlainInterface.self, .init())
        }

        #expect(failure?.transportError?.isOffline == true)
        #expect(failure?.transportError?.urlError?.code == code)
    }

    @Test("A timeout classifies as .transport(.timedOut)")
    func timeoutClassifiesAsTimedOut() async throws {
        let failure = await apiFailure {
            try await client(transport: ThrowingTransport(error: URLError(.timedOut)))
                .send(PlainInterface.self, .init())
        }

        #expect(failure?.transportError?.isTimeout == true)
    }

    @Test("Any other URLError classifies as .transport(.url) with the error preserved")
    func otherURLErrorPreservesTheError() async throws {
        let failure = await apiFailure {
            try await client(transport: ThrowingTransport(error: URLError(.cannotFindHost)))
                .send(PlainInterface.self, .init())
        }

        guard case .url(let urlError)? = failure?.transportError else {
            Issue.record("Expected .transport(.url), got \(String(describing: failure))")
            return
        }
        #expect(urlError.code == .cannotFindHost)
        #expect(failure?.transportError?.isOffline == false)
        #expect(failure?.transportError?.isTimeout == false)
    }

    @Test("A custom transport's own error type survives as .transport(.other)")
    func customTransportErrorSurvives() async throws {
        struct CustomTransportError: Error, Equatable {
            let detail: String
        }

        let thrown = CustomTransportError(detail: "socket closed")
        let failure = await apiFailure {
            try await client(transport: ThrowingTransport(error: thrown))
                .send(PlainInterface.self, .init())
        }

        guard case .other(let underlying)? = failure?.transportError else {
            Issue.record("Expected .transport(.other), got \(String(describing: failure))")
            return
        }
        #expect(underlying as? CustomTransportError == thrown)
        #expect(failure?.transportError?.urlError == nil)
    }

    @Test("URLError.cancelled surfaces as .cancelled, not as a transport failure")
    func urlErrorCancelledSurfacesAsCancelled() async throws {
        let failure = await apiFailure {
            try await client(transport: ThrowingTransport(error: URLError(.cancelled)))
                .send(PlainInterface.self, .init())
        }

        #expect(failure?.isCancelled == true)
        #expect(failure?.transportError == nil)
    }

    @Test("A transport throwing CancellationError surfaces as .cancelled")
    func cancellationErrorSurfacesAsCancelled() async throws {
        let failure = await apiFailure {
            try await client(transport: ThrowingTransport(error: CancellationError()))
                .send(PlainInterface.self, .init())
        }

        #expect(failure?.isCancelled == true)
    }

    @Test("RequestPipeline classifies transport failures the same way APIClient does")
    func pipelineClassifiesTransportFailures() async throws {
        let pipeline = RequestPipeline(
            transport: ThrowingTransport(error: URLError(.notConnectedToInternet))
        )
        let context = RequestContext(configuration: ServerConfiguration(url: testServerURL))

        let failure = await apiFailure {
            try await pipeline.send(PlainInterface.self, .init(), context: context)
        }

        #expect(failure?.transportError?.isOffline == true)
    }

}

// MARK: - Credential Failures

@Suite("APIFailure: credential failures", .timeLimit(.minutes(1)))
struct APIFailureCredentialTests {

    private struct KeychainError: Error, Equatable {
        let status: Int
    }

    @Test("A throwing token closure surfaces as .credential with the error intact")
    func throwingTokenSurfacesAsCredential() async throws {
        let thrown = KeychainError(status: -25300)
        let failure = await apiFailure {
            try await client(
                transport: StatusTransport(statusCode: 200),
                token: { throw thrown }
            ).send(BearerInterface.self, .init())
        }

        #expect(failure?.credentialError as? KeychainError == thrown)
    }

    @Test("A throwing refresh closure surfaces as .credential with the error intact")
    func throwingRefreshSurfacesAsCredential() async throws {
        let thrown = KeychainError(status: -25293)
        let failure = await apiFailure {
            try await client(
                transport: StatusTransport(statusCode: 401),
                refresh: { throw thrown }
            ).send(BearerInterface.self, .init())
        }

        #expect(failure?.credentialError as? KeychainError == thrown)
    }

    @Test("A missing credential is .request, not .credential")
    func missingCredentialIsARequestFailure() async throws {
        let failure = await apiFailure {
            try await client(
                transport: StatusTransport(statusCode: 200),
                token: { nil }
            ).send(BearerInterface.self, .init())
        }

        guard case .missingCredential(let scheme)? = failure?.requestError else {
            Issue.record("Expected .request(.missingCredential), got \(String(describing: failure))")
            return
        }
        #expect(scheme == .bearer)
        #expect(failure?.credentialError == nil)
    }

    @Test("A challenge on a client with no credential closures is .noCredentialSource")
    func challengeWithoutCredentialSource() async throws {
        let apiClient = APIClient(
            configuration: ServerConfiguration(url: testServerURL),
            transport: StatusTransport(statusCode: 401)
        )

        let failure = await apiFailure {
            try await apiClient.send(CookieAuthInterface.self, .init())
        }

        #expect(failure?.isNoCredentialSource == true)
    }

}

// MARK: - Exhaustiveness

@Suite("APIFailure: catch site", .timeLimit(.minutes(1)))
struct APIFailureCatchSiteTests {

    @Test("A caller can switch exhaustively over APIFailure with no default")
    func exhaustiveSwitchCompiles() async throws {
        func describe(_ failure: APIFailure) -> String {
            switch failure {
            case .request: return "request"
            case .transport: return "transport"
            case .response: return "response"
            case .credential: return "credential"
            case .cancelled: return "cancelled"
            case .invalidated: return "invalidated"
            case .noCredentialSource: return "noCredentialSource"
            }
        }

        #expect(describe(.invalidated) == "invalidated")
        #expect(describe(.transport(.offline(URLError(.notConnectedToInternet)))) == "transport")
    }

    @Test("Wrapping a ResponseError in .response keeps its header redaction")
    func wrappingPreservesResponseErrorRedaction() throws {
        let response = HTTPURLResponse(
            url: testServerURL,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "session=SECRET", "X-Ok": "fine"]
        )!
        let responseError = ResponseError.unknownResponseCase(
            ResponseBody(Data()),
            HTTPResponseSnapshot(response: response)
        )

        let description = String(describing: APIFailure.response(responseError))

        #expect(!description.contains("SECRET"))
        #expect(description.contains("X-Ok: fine"))
    }

    @Test("A typed catch matches a case directly, with no cast")
    func typedCatchMatchesACaseDirectly() async throws {
        let apiClient = client(transport: ThrowingTransport(error: URLError(.timedOut)))

        do {
            _ = try await apiClient.send(PlainInterface.self, .init())
            Issue.record("Expected a failure")
        } catch .transport(let error) {
            #expect(error.isTimeout)
        } catch {
            Issue.record("Expected .transport, got \(error)")
        }
    }

}
