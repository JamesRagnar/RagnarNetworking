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

extension URLSession: DataTaskProvider {}
