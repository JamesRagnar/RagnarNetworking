//
//  RequestService+DataTask.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-19.
//

import Foundation

public protocol RequestService {
        
    var loggingService: LoggingService? { get }
    
    var dataTaskProvider: any DataTaskProvider { get }
    
    func serverConfiguration() throws -> ServerConfiguration
    
    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters
    ) async throws -> T.Response

    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ constructor: InterfaceConstructor.Type
    ) async throws -> T.Response

}

public extension RequestService {
    
    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters
    ) async throws -> T.Response {
        try await dataTaskProvider.dataTask(
            interface,
            parameters,
            try serverConfiguration()
        )
    }

    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ constructor: InterfaceConstructor.Type
    ) async throws -> T.Response {
        try await dataTaskProvider.dataTask(
            interface,
            parameters,
            try serverConfiguration(),
            constructor: constructor
        )
    }
    
}
