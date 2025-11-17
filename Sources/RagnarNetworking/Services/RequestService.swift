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
        
        
//        var interfaceRequest: URLRequest!
//        do {
//            interfaceRequest = try request(interface, parameters)
//        } catch {
//            loggingService?
//                .log(
//                    source: .requestService,
//                    level: .error,
//                    message: "Failed to create request - \(error.localizedDescription)"
//                )
//            
//            throw error
//        }
//        
//        loggingService?
//            .log(
//                source: .requestService,
//                level: .debug,
//                message: "\(interfaceRequest.httpMethod ?? "") - \(interfaceRequest.url?.description ?? "")"
//            )
//
//        do {
//            return try T.handle(
//                try await dataTaskProvider.data(for: interfaceRequest)
//            )
//        } catch {
//            loggingService?
//                .log(
//                    source: .requestService,
//                    level: .error,
//                    message: "Request error - \(error.localizedDescription)"
//                )
//            
//            throw error
//        }
    }
    
}
