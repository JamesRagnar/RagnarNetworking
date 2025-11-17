//
//  DataTaskProvider.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-21.
//

import Foundation.NSURLSession

public protocol DataTaskProvider {
    
    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) async throws -> T.Response

    func data(for request: URLRequest) async throws -> (Data, URLResponse)

}

public extension DataTaskProvider {
    
    func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) async throws -> T.Response {
        let request = try URLRequest(
            requestParameters: parameters,
            serverConfiguration: configuration
        )
        
        let response = try await data(for: request)
        
        return try T.handle(response)
    }

}

extension URLSession: DataTaskProvider {}
