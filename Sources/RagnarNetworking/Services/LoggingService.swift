//
//  LoggingService.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-23.
//

public enum LoggingSource {

    case requestService

    case socketService

}

public enum LogLevel {

    case debug

    case error

}

public protocol LoggingService: AnyObject {

    func log(
        source: LoggingSource,
        level: LogLevel,
        message: String
    )

}
