//
//  RequestService+DataTask.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-19.
//

import Foundation

public protocol RequestService {
        
    var loggingService: LoggingService? { get }
    
    var dataTaskProvider: DataTaskProvider { get }
    
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
        var interfaceRequest: URLRequest!
        do {
            interfaceRequest = try request(interface, parameters)
        } catch {
            loggingService?
                .log(
                    source: .requestService,
                    level: .error,
                    message: "Failed to create request - \(error.localizedDescription)"
                )
            
            throw error
        }
        
        loggingService?
            .log(
                source: .requestService,
                level: .debug,
                message: "\(interfaceRequest.httpMethod ?? "") - \(interfaceRequest.url?.description ?? "")"
            )

        do {
            return try T.handle(
                try await dataTaskProvider.data(for: interfaceRequest)
            )
        } catch {
            loggingService?
                .log(
                    source: .requestService,
                    level: .error,
                    message: "Request error - \(error.localizedDescription)"
                )
            
            throw error
        }
    }
    
    func request<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters
    ) throws -> URLRequest {
        return try URLRequest(
            requestParameters: parameters,
            serverConfiguration: try serverConfiguration()
        )
    }

}

public extension RequestService {
    
    

}
