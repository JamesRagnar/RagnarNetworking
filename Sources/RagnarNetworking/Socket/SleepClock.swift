//
//  SleepClock.swift
//  RagnarNetworking
//

import Foundation

/// Abstracts suspending for a duration, so timing-dependent behavior (reconnect backoff,
/// heartbeat timeouts) can be driven deterministically in tests instead of waiting on the
/// wall clock.
protocol SleepClock: Sendable {
    func sleep(for duration: Duration) async throws
}

/// The real clock. Suspends for the actual duration via `Task.sleep`.
struct SystemSleepClock: SleepClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
