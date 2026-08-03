//
//  ResponseContract.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation
import OSLog

/// The successful and failed status-code semantics for an Interface response.
///
/// Every contract requires at least one success matcher. A successful match always builds the
/// Interface's declared `Response`; failure cases cannot select successful decoding.
///
/// Matching priority:
/// 1. Exact matches
/// 2. Success ranges in declaration order
/// 3. Failure ranges in declaration order
///
/// An exact matcher therefore overrides any range. When the same exact code is declared more
/// than once, the first declaration wins and a developer diagnostic is emitted.
public struct ResponseContract<Output: InterfaceResponse & Sendable>: Sendable {

    private let exactMatches: [Int: ResponseMatch]
    private let successRanges: [Range<Int>]
    private let failureRanges: [(range: Range<Int>, outcome: FailureOutcome)]

    /// The status-code declarations without the generic successful output binding.
    public let statuses: ResponseStatusContract

    /// Creates a response contract with at least one successful status matcher.
    ///
    /// - Parameters:
    ///   - firstSuccess: A status matcher that builds the Interface's declared `Response`.
    ///   - additionalSuccesses: Other status matchers that build the same `Response` type.
    ///   - failures: Status matchers that throw declared failures.
    public init(
        success firstSuccess: StatusCodeMatcher,
        additionalSuccesses: [StatusCodeMatcher] = [],
        failures: [FailureResponseCase] = []
    ) {
        var exactMatches: [Int: ResponseMatch] = [:]
        var exactCodes: Set<Int> = []
        var successRanges: [Range<Int>] = []
        var failureRanges: [(range: Range<Int>, outcome: FailureOutcome)] = []

        for matcher in [firstSuccess] + additionalSuccesses {
            switch matcher {
            case .exact(let code):
                Self.insertExact(
                    code,
                    match: .success,
                    into: &exactMatches,
                    exactCodes: &exactCodes
                )

            case .range(let range):
                successRanges.append(range)
            }
        }

        for failure in failures {
            switch failure.matcher {
            case .exact(let code):
                Self.insertExact(
                    code,
                    match: .failure(failure.outcome),
                    into: &exactMatches,
                    exactCodes: &exactCodes
                )

            case .range(let range):
                failureRanges.append((range, failure.outcome))
            }
        }

        self.exactMatches = exactMatches
        self.successRanges = successRanges
        self.failureRanges = failureRanges
        self.statuses = ResponseStatusContract(exactCodes: exactCodes)
    }

    /// Resolves a status code to successful decoding, a declared failure, or no match.
    public func match(_ statusCode: Int) -> ResponseMatch? {
        if let exact = exactMatches[statusCode] {
            return exact
        }

        for range in successRanges where range.contains(statusCode) {
            return .success
        }

        for failure in failureRanges where failure.range.contains(statusCode) {
            return .failure(failure.outcome)
        }

        return nil
    }

    private static func insertExact(
        _ code: Int,
        match: ResponseMatch,
        into exactMatches: inout [Int: ResponseMatch],
        exactCodes: inout Set<Int>
    ) {
        guard exactMatches[code] == nil else {
            Logger.diagnostics.warning(
                "RagnarNetworking: duplicate exact response case \(code, privacy: .public). Keeping first."
            )
            return
        }

        exactMatches[code] = match
        exactCodes.insert(code)
    }

}

/// A matched response-contract action.
public enum ResponseMatch: Sendable {

    /// Build the Interface's declared `Response` from the response body and metadata.
    case success

    /// Throw the declared failure.
    case failure(FailureOutcome)

}

/// The action to take for a matched failure status.
public enum FailureOutcome: Sendable {

    /// Throw the given error with the response body preserved in `ResponseError`.
    case error(any Error & Sendable)

    /// Decode the response body as a typed error and throw it.
    case decodeError(body: @Sendable (Data, ResponseDecoder) throws -> any Error & Sendable)

    /// Decodes a failure body using the response's configured decoder.
    public static func decodeError<T: Decodable & Sendable & Error>(
        _ type: T.Type
    ) -> FailureOutcome {
        .decodeError(body: { data, decoder in
            try decoder.decode(T.self, from: data)
        })
    }

}

/// Defines how a status code is matched.
public enum StatusCodeMatcher: Sendable {

    case exact(Int)

    case range(Range<Int>)

    /// 100..<200
    public static let informational = StatusCodeMatcher.range(100..<200)

    /// 200..<300
    public static let success = StatusCodeMatcher.range(200..<300)

    /// 300..<400
    public static let redirection = StatusCodeMatcher.range(300..<400)

    /// 400..<500
    public static let clientError = StatusCodeMatcher.range(400..<500)

    /// 500..<600
    public static let serverError = StatusCodeMatcher.range(500..<600)

    /// Creates a matcher from a closed range.
    /// - Note: Closed ranges ending in `Int.max` do not match `Int.max`.
    public static func range(_ range: ClosedRange<Int>) -> StatusCodeMatcher {
        let upperExclusive = range.upperBound == Int.max
        ? range.upperBound
        : range.upperBound + 1

        return .range(range.lowerBound..<upperExclusive)
    }

}

/// Associates a status-code matcher with a failure outcome.
public struct FailureResponseCase: Sendable {

    public let matcher: StatusCodeMatcher
    public let outcome: FailureOutcome

    /// Exact status code match.
    public static func code(
        _ code: Int,
        _ outcome: FailureOutcome
    ) -> FailureResponseCase {
        .init(matcher: .exact(code), outcome: outcome)
    }

    /// Match any status code in an open range.
    public static func range(
        _ range: Range<Int>,
        _ outcome: FailureOutcome
    ) -> FailureResponseCase {
        .init(matcher: .range(range), outcome: outcome)
    }

    /// Match any status code in a closed range.
    public static func range(
        _ range: ClosedRange<Int>,
        _ outcome: FailureOutcome
    ) -> FailureResponseCase {
        .init(matcher: .range(range), outcome: outcome)
    }

    /// 100..<200
    public static func informational(_ outcome: FailureOutcome) -> FailureResponseCase {
        .init(matcher: .informational, outcome: outcome)
    }

    /// 200..<300
    public static func success(_ outcome: FailureOutcome) -> FailureResponseCase {
        .init(matcher: .success, outcome: outcome)
    }

    /// 300..<400
    public static func redirection(_ outcome: FailureOutcome) -> FailureResponseCase {
        .init(matcher: .redirection, outcome: outcome)
    }

    /// 400..<500
    public static func clientError(_ outcome: FailureOutcome) -> FailureResponseCase {
        .init(matcher: .clientError, outcome: outcome)
    }

    /// 500..<600
    public static func serverError(_ outcome: FailureOutcome) -> FailureResponseCase {
        .init(matcher: .serverError, outcome: outcome)
    }

}

/// The status declarations from a response contract, erased from its successful output type.
public struct ResponseStatusContract: Sendable {

    private let exactCodes: Set<Int>

    fileprivate init(exactCodes: Set<Int>) {
        self.exactCodes = exactCodes
    }

    /// Whether the endpoint explicitly declares this exact status code.
    public func declaresExact(_ statusCode: Int) -> Bool {
        exactCodes.contains(statusCode)
    }

}
