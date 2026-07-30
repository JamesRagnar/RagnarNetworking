//
//  Logger+RagnarNetworking.swift
//  RagnarNetworking
//

import OSLog

extension Logger {
    static let socket = Logger(subsystem: "RagnarNetworking", category: "Socket")
    static let network = Logger(subsystem: "RagnarNetworking", category: "Network")
    static let responseMap = Logger(subsystem: "RagnarNetworking", category: "ResponseMap")
    static let diagnostics = Logger(subsystem: "RagnarNetworking", category: "Diagnostics")
}
