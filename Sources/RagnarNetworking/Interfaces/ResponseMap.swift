//
//  ResponseMap.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

// MARK: - Response Outcome

/// The action to take when a response status code is matched.
public enum ResponseOutcome {

    /// Decode the response body as the Interface's Response type.
    case decode

    /// Throw the given error (body available as raw data in ResponseError).
    case error(Error)

    /// Decode the response body as a typed error and throw it.
    /// The decoded error is accessible via ResponseError.decoded.
    case decodeError(body: @Sendable (Data) throws -> any Error & Sendable)

    /// Convenience: decode error body as the given type using JSONDecoder.
    public static func decodeError<T: Decodable & Sendable & Error>(
        _ type: T.Type
    ) -> ResponseOutcome {
        .decodeError(body: { data in
            try JSONDecoder().decode(T.self, from: data)
        })
    }

}

// MARK: - Status Code Matching

/// Defines how a status code is matched for a response case.
public enum StatusCodeMatcher {

    case exact(Int)

    case range(Range<Int>)

}

/// Associates a status code matcher with a response outcome.
public struct ResponseCase {

    let matcher: StatusCodeMatcher
    let outcome: ResponseOutcome

    /// Exact status code match.
    public static func code(
        _ code: Int,
        _ outcome: ResponseOutcome
    ) -> ResponseCase {
        .init(
            matcher: .exact(code),
            outcome: outcome
        )
    }

    /// Match any status code in the provided open range.
    public static func range(
        _ range: Range<Int>,
        _ outcome: ResponseOutcome
    ) -> ResponseCase {
        .init(
            matcher: .range(range),
            outcome: outcome
        )
    }

    /// Match any status code in the provided closed range.
    /// - Note: The upper bound is converted to an exclusive upper bound.
    public static func range(
        _ range: ClosedRange<Int>,
        _ outcome: ResponseOutcome
    ) -> ResponseCase {
        let upperExclusive = range.upperBound == Int.max
        ? range.upperBound
        : range.upperBound + 1

        return .init(
            matcher: .range(range.lowerBound..<upperExclusive),
            outcome: outcome
        )
    }

    /// 100..<200
    public static func informational(_ outcome: ResponseOutcome) -> ResponseCase {
        .range(100..<200, outcome)
    }

    /// 200..<300
    public static func success(_ outcome: ResponseOutcome) -> ResponseCase {
        .range(200..<300, outcome)
    }

    /// 300..<400
    public static func redirection(_ outcome: ResponseOutcome) -> ResponseCase {
        .range(300..<400, outcome)
    }

    /// 400..<500
    public static func clientError(_ outcome: ResponseOutcome) -> ResponseCase {
        .range(400..<500, outcome)
    }

    /// 500..<600
    public static func serverError(_ outcome: ResponseOutcome) -> ResponseCase {
        .range(500..<600, outcome)
    }

}

// MARK: - Response Map

/// A status-code-to-outcome mapping with range support.
///
/// Matching priority:
/// 1. Exact matches (O(1))
/// 2. Range matches in the order they were defined
public struct ResponseMap: ExpressibleByArrayLiteral {

    private let exactCases: [Int: ResponseOutcome]
    private let rangeCases: [(range: Range<Int>, outcome: ResponseOutcome)]

    public init(arrayLiteral elements: ResponseCase...) {
        self.init(elements)
    }

    public init(_ cases: [ResponseCase]) {
        var exact: [Int: ResponseOutcome] = [:]
        var ranges: [(range: Range<Int>, outcome: ResponseOutcome)] = []

        for responseCase in cases {
            switch responseCase.matcher {
            case .exact(let code):
                exact[code] = responseCase.outcome

            case .range(let range):
                ranges.append((range: range, outcome: responseCase.outcome))
            }
        }

        self.exactCases = exact
        self.rangeCases = ranges
    }

    /// Returns the first matching outcome for the given status code.
    func match(_ statusCode: Int) -> ResponseOutcome? {
        if let exact = exactCases[statusCode] {
            return exact
        }

        for rangeCase in rangeCases {
            if rangeCase.range.contains(statusCode) {
                return rangeCase.outcome
            }

            if statusCode == Int.max, rangeCase.range.upperBound == Int.max {
                return rangeCase.outcome
            }
        }

        return nil
    }

}
