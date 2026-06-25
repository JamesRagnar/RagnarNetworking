//
//  Logger+RagnarNetworking.swift
//  RagnarNetworking
//

import OSLog

extension Logger {
    static let socket = Logger(subsystem: "RagnarNetworking", category: "Socket")
    static let network = Logger(subsystem: "RagnarNetworking", category: "Network")
    static let responseMap = Logger(subsystem: "RagnarNetworking", category: "ResponseMap")
}

/// Log via OSLog, guarded by `RagnarNetworkingConfig.loggingEnabled`.
@inline(__always)
func rnLog(_ logger: Logger, level: OSLogType = .debug, _ message: @autoclosure () -> String) {
    guard RagnarNetworkingConfig.loggingEnabled else { return }
    let msg = message()
    logger.log(level: level, "\(msg, privacy: .public)")
}
