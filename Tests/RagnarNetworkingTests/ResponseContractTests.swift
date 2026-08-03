//
//  ResponseContractTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

@testable import RagnarNetworking
import Testing

@Suite("ResponseContract Tests", .timeLimit(.minutes(1)))
struct ResponseContractTests {

    enum TestError: Error, Equatable {
        case first
        case second
    }

    struct DecodedError: Error, Decodable, Sendable, Equatable {
        let message: String
    }

    @Test("Exact success matches take priority over failure ranges")
    func testExactSuccessBeatsFailureRange() {
        let contract = ResponseContract<EmptyResponse>(
            success: .exact(201),
            failures: [.range(200..<300, .error(TestError.first))]
        )

        #expect(isSuccess(contract.match(201)))
    }

    @Test("Exact failure matches take priority over success ranges")
    func testExactFailureBeatsSuccessRange() {
        let contract = ResponseContract<EmptyResponse>(
            success: .range(200..<300),
            failures: [.code(202, .error(TestError.first))]
        )

        #expect(matchesError(contract.match(202), expected: .first))
    }

    @Test("Failure ranges follow definition order")
    func testFailureRangeOrder() {
        let contract = ResponseContract<EmptyResponse>(
            success: .exact(200),
            failures: [
                .range(400..<500, .error(TestError.first)),
                .range(400..<600, .error(TestError.second))
            ]
        )

        #expect(matchesError(contract.match(404), expected: .first))
    }

    @Test("Additional success matchers build the same output")
    func testAdditionalSuccesses() {
        let contract = ResponseContract<EmptyResponse>(
            success: .exact(200),
            additionalSuccesses: [.exact(201), .range(202..<205)]
        )

        #expect(isSuccess(contract.match(200)))
        #expect(isSuccess(contract.match(201)))
        #expect(isSuccess(contract.match(204)))
    }

    @Test("Closed ranges include their upper bound")
    func testClosedRangeUpperBound() {
        let contract = ResponseContract<EmptyResponse>(success: .range(200...204))

        #expect(isSuccess(contract.match(204)))
        #expect(contract.match(199) == nil)
        #expect(contract.match(205) == nil)
    }

    @Test("Category matchers map to expected ranges")
    func testCategoryMatchers() {
        let contract = ResponseContract<EmptyResponse>(
            success: .success,
            failures: [
                .informational(.error(TestError.first)),
                .redirection(.error(TestError.second)),
                .clientError(.error(TestError.first)),
                .serverError(.error(TestError.second))
            ]
        )

        #expect(isSuccess(contract.match(204)))
        #expect(matchesError(contract.match(102), expected: .first))
        #expect(matchesError(contract.match(301), expected: .second))
        #expect(matchesError(contract.match(404), expected: .first))
        #expect(matchesError(contract.match(503), expected: .second))
    }

    @Test("Closed ranges ending at Int.max do not match Int.max")
    func testClosedRangeIntMaxUpperBoundDoesNotMatch() {
        let lower = Int.max - 2
        let contract = ResponseContract<EmptyResponse>(success: .range(lower...Int.max))

        #expect(isSuccess(contract.match(Int.max - 1)))
        #expect(contract.match(Int.max) == nil)
    }

    @Test("Duplicate exact matches keep the first declaration")
    func testExactDuplicateKeepsFirst() {
        let contract = ResponseContract<EmptyResponse>(
            success: .exact(200),
            failures: [.code(200, .error(TestError.first))]
        )

        #expect(isSuccess(contract.match(200)))
    }

    @Test("decodeError failures are preserved and callable")
    func testDecodeErrorOutcome() throws {
        let contract = ResponseContract<EmptyResponse>(
            success: .exact(200),
            failures: [.code(400, .decodeError(DecodedError.self))]
        )

        guard case .failure(.decodeError(let decodeBody))? = contract.match(400) else {
            #expect(Bool(false), "Expected decodeError failure")
            return
        }

        let data = #"{"message":"fail"}"#.data(using: .utf8)!
        let decoded = try decodeBody(data, ResponseDecoder())
        #expect((decoded as? DecodedError)?.message == "fail")
    }

    @Test("decodeError uses the supplied decoder")
    func testDecodeErrorUsesSuppliedDecoder() throws {
        struct SnakeCaseError: Decodable, Sendable, Error {
            let errorMessage: String
        }

        let contract = ResponseContract<EmptyResponse>(
            success: .exact(200),
            failures: [.code(400, .decodeError(SnakeCaseError.self))]
        )

        guard case .failure(.decodeError(let decodeBody))? = contract.match(400) else {
            #expect(Bool(false), "Expected decodeError failure")
            return
        }

        let data = #"{"error_message":"fail"}"#.data(using: .utf8)!
        let decoded = try decodeBody(
            data,
            ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
        )
        #expect((decoded as? SnakeCaseError)?.errorMessage == "fail")
    }

    @Test("Unmatched status codes return nil")
    func testNoMatch() {
        let contract = ResponseContract<EmptyResponse>(success: .exact(200))

        #expect(contract.match(404) == nil)
    }

    @Test("Status view records exact success and failure declarations")
    func testStatusViewExactDeclarations() {
        let contract = ResponseContract<EmptyResponse>(
            success: .exact(200),
            additionalSuccesses: [.success],
            failures: [.code(401, .error(TestError.first)), .clientError(.error(TestError.second))]
        )

        #expect(contract.statuses.declaresExact(200))
        #expect(contract.statuses.declaresExact(401))
        #expect(!contract.statuses.declaresExact(204))
        #expect(!contract.statuses.declaresExact(404))
    }

}

private func isSuccess(_ match: ResponseMatch?) -> Bool {
    guard case .success? = match else { return false }
    return true
}

private func matchesError(
    _ match: ResponseMatch?,
    expected: ResponseContractTests.TestError
) -> Bool {
    guard case .failure(.error(let error as ResponseContractTests.TestError))? = match else {
        return false
    }
    return error == expected
}
