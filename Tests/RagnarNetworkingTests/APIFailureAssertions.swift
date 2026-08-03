//
//  APIFailureAssertions.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Capturing the Thrown Failure

/// Runs `operation` and returns the `APIFailure` it threw, or `nil` after recording an issue.
///
/// `#expect(throws:)` returns the thrown error only in the Swift Testing bundled with Xcode 26
/// and later; under Xcode 16.2 the same call returns `Void`. The package is tested against both,
/// so tests capture the failure here rather than relying on that return value.
///
/// The closure's throw type is untyped rather than `APIFailure`, so this also accepts a
/// `Task.value` whose failure type is erased. It is generic over the return type so a call site
/// can name the throwing expression directly without discarding its result.
func apiFailure<T>(
    _ operation: () async throws -> T
) async -> APIFailure? {
    do {
        _ = try await operation()
        Issue.record("Expected an APIFailure, but the operation succeeded.")
        return nil
    } catch let failure as APIFailure {
        return failure
    } catch {
        Issue.record("Expected an APIFailure, but got \(error).")
        return nil
    }
}

// MARK: - Assertion Helpers

/// `APIFailure` cannot be `Equatable` - `.credential`, `.transport`, and `.response` carry
/// values that are not - so assertions match on the case rather than comparing values.
extension APIFailure {

    var isInvalidated: Bool {
        if case .invalidated = self {
            return true
        }
        return false
    }

    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }

    var isNoCredentialSource: Bool {
        if case .noCredentialSource = self {
            return true
        }
        return false
    }

    var credentialError: (any Error)? {
        if case .credential(let error) = self {
            return error
        }
        return nil
    }

    var transportError: TransportError? {
        if case .transport(let error) = self {
            return error
        }
        return nil
    }

    var responseError: ResponseError? {
        if case .response(let error) = self {
            return error
        }
        return nil
    }

    var requestError: RequestError? {
        if case .request(let error) = self {
            return error
        }
        return nil
    }

}
