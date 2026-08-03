//
//  TransportErrorTests.swift
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

/// Throws whatever it is handed, so a test can drive the classification directly.
private struct ThrowingTransport: Transport {
    let error: any Error

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw error
    }
}

private func client(transport: any Transport) -> APIClient {
    APIClient(
        configuration: ServerConfiguration(url: testServerURL),
        transport: transport
    )
}

// MARK: - Classification

@Suite("TransportError classification", .timeLimit(.minutes(1)))
struct TransportErrorClassificationTests {

    @Test(
        "Offline URLError codes classify as .offline",
        arguments: [
            URLError.Code.notConnectedToInternet,
            .networkConnectionLost,
            .dataNotAllowed,
            .internationalRoamingOff
        ]
    )
    func offlineCodesClassifyAsOffline(code: URLError.Code) async throws {
        let failure = await thrownError(TransportError.self) {
            try await client(transport: ThrowingTransport(error: URLError(code)))
                .send(PlainInterface.self, .init())
        }

        #expect(failure?.isOffline == true)
        #expect(failure?.isTimeout == false)
        #expect(failure?.urlError?.code == code)
    }

    @Test("A timeout classifies as .timedOut")
    func timeoutClassifiesAsTimedOut() async throws {
        let failure = await thrownError(TransportError.self) {
            try await client(transport: ThrowingTransport(error: URLError(.timedOut)))
                .send(PlainInterface.self, .init())
        }

        #expect(failure?.isTimeout == true)
        #expect(failure?.isOffline == false)
    }

    @Test("Any other URLError classifies as .url with the error preserved")
    func otherURLErrorPreservesTheError() async throws {
        let failure = await thrownError(TransportError.self) {
            try await client(transport: ThrowingTransport(error: URLError(.cannotFindHost)))
                .send(PlainInterface.self, .init())
        }

        guard case .url(let urlError)? = failure else {
            Issue.record("Expected .url, got \(String(describing: failure))")
            return
        }
        #expect(urlError.code == .cannotFindHost)
        #expect(failure?.isOffline == false)
        #expect(failure?.isTimeout == false)
    }

    @Test("A custom transport's own error type survives as .other")
    func customTransportErrorSurvives() async throws {
        struct CustomTransportError: Error, Equatable {
            let detail: String
        }

        let thrown = CustomTransportError(detail: "socket closed")
        let failure = await thrownError(TransportError.self) {
            try await client(transport: ThrowingTransport(error: thrown))
                .send(PlainInterface.self, .init())
        }

        guard case .other(let underlying)? = failure else {
            Issue.record("Expected .other, got \(String(describing: failure))")
            return
        }
        #expect(underlying as? CustomTransportError == thrown)
        #expect(failure?.urlError == nil)
    }

    @Test("RequestPipeline classifies the same way whether or not APIClient is in front of it")
    func pipelineClassifiesTheSameWay() async throws {
        let pipeline = RequestPipeline(
            transport: ThrowingTransport(error: URLError(.notConnectedToInternet))
        )
        let context = RequestContext(configuration: ServerConfiguration(url: testServerURL))

        let failure = await thrownError(TransportError.self) {
            try await pipeline.send(PlainInterface.self, .init(), context: context)
        }

        #expect(failure?.isOffline == true)
    }

}

// MARK: - Cancellation

@Suite("TransportError: cancellation is not a transport failure", .timeLimit(.minutes(1)))
struct TransportCancellationTests {

    @Test("URLError.cancelled surfaces as CancellationError, not TransportError")
    func urlErrorCancelledSurfacesAsCancellationError() async throws {
        await #expect(throws: CancellationError.self) {
            try await client(transport: ThrowingTransport(error: URLError(.cancelled)))
                .send(PlainInterface.self, .init())
        }
    }

    @Test("A transport throwing CancellationError propagates it unchanged")
    func cancellationErrorPropagates() async throws {
        await #expect(throws: CancellationError.self) {
            try await client(transport: ThrowingTransport(error: CancellationError()))
                .send(PlainInterface.self, .init())
        }
    }

}

// MARK: - Catch Site

@Suite("TransportError: catch site", .timeLimit(.minutes(1)))
struct TransportErrorCatchSiteTests {

    @Test("A caller distinguishes offline from other failures without matching on URLError.Code")
    func catchSiteDistinguishesOffline() async throws {
        let apiClient = client(
            transport: ThrowingTransport(error: URLError(.notConnectedToInternet))
        )

        do {
            _ = try await apiClient.send(PlainInterface.self, .init())
            Issue.record("Expected a failure")
        } catch let failure as TransportError {
            #expect(failure.isOffline)
            #expect(failure.errorDescription == "The Internet connection appears to be offline.")
        }
    }

    @Test("A caller can switch exhaustively over TransportError with no default")
    func exhaustiveSwitchCompiles() {
        func describe(_ failure: TransportError) -> String {
            switch failure {
            case .offline: return "offline"
            case .timedOut: return "timedOut"
            case .url: return "url"
            case .other: return "other"
            }
        }

        #expect(describe(.offline(URLError(.notConnectedToInternet))) == "offline")
        #expect(describe(.timedOut(URLError(.timedOut))) == "timedOut")
    }

}
