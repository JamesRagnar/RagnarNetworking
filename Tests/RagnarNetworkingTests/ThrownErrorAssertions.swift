//
//  ThrownErrorAssertions.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation
@testable import RagnarNetworking
import Testing

/// Runs `operation` and returns the error it threw as `E`, or `nil` after recording an issue.
///
/// `#expect(throws:)` returns the thrown error only in the Swift Testing bundled with Xcode 26
/// and later; under Xcode 16.2 the same call returns `Void`. The package is tested against both,
/// so tests that inspect the thrown value capture it here instead. Tests that only assert the
/// error's *type* can keep using `#expect(throws:)` directly, which works on both.
///
/// Generic over the closure's return type so a call site can name the throwing expression
/// directly without discarding its result.
func thrownError<E: Error, T>(
    _ type: E.Type,
    from operation: () async throws -> T
) async -> E? {
    do {
        _ = try await operation()
        Issue.record("Expected \(E.self), but the operation succeeded.")
        return nil
    } catch let error as E {
        return error
    } catch {
        Issue.record("Expected \(E.self), but got \(error).")
        return nil
    }
}
