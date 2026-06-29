//
//  RagnarNetworkingLogging.swift
//  RagnarNetworking
//

import Foundation

/// Immutable logging configuration for `RagnarNetworking`.
public struct RagnarNetworkingLogging: Sendable {

    /// Whether runtime `RagnarNetworking` log output is enabled.
    public let enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public static let disabled = Self(enabled: false)

}
