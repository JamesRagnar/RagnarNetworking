//
//  RagnarNetworkingConfig.swift
//  RagnarNetworking
//

import Foundation

/// Package-level configuration for RagnarNetworking.
public enum RagnarNetworkingConfig {

    /// Set to `false` to suppress all RagnarNetworking log output.
    ///
    /// Not thread-safe. Set once at app launch before starting any requests or opening connections.
    /// All log categories (network, socket) respect this flag.
    ///
    ///     RagnarNetworkingConfig.loggingEnabled = false
    ///
    /// Alternatively, filter by subsystem in Console.app or via:
    ///
    ///     log stream --predicate 'subsystem == "RagnarNetworking"'
    nonisolated(unsafe) public static var loggingEnabled: Bool = true

}
