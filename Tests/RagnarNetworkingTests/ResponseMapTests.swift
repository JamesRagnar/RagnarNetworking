//
//  ResponseMapTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

@testable import RagnarNetworking
import Testing

@Suite("ResponseMap Tests")
struct ResponseMapTests {

    enum TestError: Error, Equatable {
        case first
        case second
    }

    struct DecodedError: Error, Decodable, Sendable, Equatable {
        let message: String
    }

    @Test("Exact matches take priority over ranges")
    func testExactBeatsRange() {
        let map: ResponseMap = [
            .range(200..<300, .error(TestError.first)),
            .code(201, .decode)
        ]

        guard let outcome = map.match(201) else {
            #expect(Bool(false), "Expected a match")
            return
        }

        switch outcome {
        case .decode:
            // Expected
            break

        default:
            #expect(Bool(false), "Expected exact match to win")
        }
    }

    @Test("Range matches follow definition order")
    func testRangeOrder() {
        let map: ResponseMap = [
            .range(200..<300, .error(TestError.first)),
            .range(200..<400, .error(TestError.second))
        ]

        guard let outcome = map.match(201) else {
            #expect(Bool(false), "Expected a match")
            return
        }

        switch outcome {
        case .error(let error as TestError):
            #expect(error == .first)

        default:
            #expect(Bool(false), "Expected first range to win")
        }
    }

    @Test("Multiple non-overlapping ranges match independently")
    func testMultipleNonOverlappingRanges() {
        let map: ResponseMap = [
            .range(400..<500, .error(TestError.first)),
            .range(500..<600, .error(TestError.second))
        ]

        switch map.match(450) {
        case .error(let error as TestError):
            #expect(error == .first)

        default:
            #expect(Bool(false), "Expected first range match")
        }

        switch map.match(550) {
        case .error(let error as TestError):
            #expect(error == .second)

        default:
            #expect(Bool(false), "Expected second range match")
        }
    }

    @Test("Closed ranges include their upper bound")
    func testClosedRangeUpperBound() {
        let map: ResponseMap = [
            .range(200...204, .decode)
        ]

        guard let outcome = map.match(204) else {
            #expect(Bool(false), "Expected a match at upper bound")
            return
        }

        switch outcome {
        case .decode:
            break

        default:
            #expect(Bool(false), "Expected closed range upper bound to match")
        }
    }

    @Test("Closed ranges exclude values outside bounds")
    func testClosedRangeExcludesOutOfBounds() {
        let map: ResponseMap = [
            .range(200...204, .decode)
        ]

        #expect(map.match(199) == nil)
        #expect(map.match(205) == nil)
    }

    @Test("Category helpers map to expected ranges")
    func testCategoryHelpers() {
        let map: ResponseMap = [
            .informational(.error(TestError.first)),
            .success(.decode),
            .redirection(.error(TestError.second)),
            .clientError(.error(TestError.first)),
            .serverError(.error(TestError.second))
        ]

        #expect(isDecode(map.match(204)) == true)
        #expect(matchesError(map.match(102), expected: .first) == true)
        #expect(matchesError(map.match(301), expected: .second) == true)
        #expect(matchesError(map.match(404), expected: .first) == true)
        #expect(matchesError(map.match(503), expected: .second) == true)
    }

    @Test("Open ranges exclude the upper bound")
    func testOpenRangeUpperBoundExcluded() {
        let map: ResponseMap = [
            .range(200..<300, .decode)
        ]

        #expect(map.match(300) == nil)
    }

    @Test("Closed ranges with Int.max do not match Int.max")
    func testClosedRangeIntMaxUpperBoundDoesNotMatch() {
        let lower = Int.max - 2
        let map: ResponseMap = [
            .range(lower...Int.max, .decode)
        ]

        #expect(map.match(Int.max) == nil)
    }

    @Test("Exact duplicates resolve to the last definition")
    func testExactDuplicateOverrides() {
        let map: ResponseMap = [
            .code(200, .error(TestError.first)),
            .code(200, .error(TestError.second))
        ]

        guard let outcome = map.match(200) else {
            #expect(Bool(false), "Expected a match")
            return
        }

        switch outcome {
        case .error(let error as TestError):
            #expect(error == .second)

        default:
            #expect(Bool(false), "Expected last exact case to win")
        }
    }

    @Test("decodeError outcome is preserved and callable")
    func testDecodeErrorOutcome() throws {
        let map: ResponseMap = [
            .code(400, .decodeError(DecodedError.self))
        ]

        guard let outcome = map.match(400) else {
            #expect(Bool(false), "Expected a match")
            return
        }

        switch outcome {
        case .decodeError(let decodeBody):
            let data = #"{"message":"fail"}"#.data(using: .utf8)!
            let decoded = try decodeBody(data)
            let typed = decoded as? DecodedError
            #expect(typed?.message == "fail")

        default:
            #expect(Bool(false), "Expected decodeError outcome")
        }
    }

    @Test("noContent outcome is preserved")
    func testNoContentOutcome() {
        let map: ResponseMap = [
            .code(204, .noContent)
        ]

        guard let outcome = map.match(204) else {
            #expect(Bool(false), "Expected a match")
            return
        }

        switch outcome {
        case .noContent:
            break

        default:
            #expect(Bool(false), "Expected noContent outcome")
        }
    }

    @Test("match returns nil when no cases apply")
    func testNoMatch() {
        let map: ResponseMap = [
            .code(200, .decode)
        ]

        #expect(map.match(404) == nil)
    }

}

private func isDecode(_ outcome: ResponseOutcome?) -> Bool {
    guard let outcome else { return false }
    switch outcome {
    case .decode:
        return true

    default:
        return false
    }
}

private func matchesError(_ outcome: ResponseOutcome?, expected: ResponseMapTests.TestError) -> Bool {
    guard let outcome else { return false }
    switch outcome {
    case .error(let error as ResponseMapTests.TestError):
        return error == expected

    default:
        return false
    }
}
