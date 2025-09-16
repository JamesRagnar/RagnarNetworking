//
//  DataTaskProvider.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-21.
//

import Foundation.NSURLSession

public protocol DataTaskProvider {
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

}

public extension DataTaskProvider {
    
    static func dataTask<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration,
        _ dataTaskProvider: DataTaskProvider
    ) async throws -> T.Response {
        let request = try URLRequest(
            requestParameters: parameters,
            serverConfiguration: configuration
        )
        
        return try T.handle(
            try await dataTaskProvider.data(for: request)
        )
    }

}

extension URLSession: DataTaskProvider {}
