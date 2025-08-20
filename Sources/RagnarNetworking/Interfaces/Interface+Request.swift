//
//  Interface+Request.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

public enum RequestError: Error {
    
    /// The Server Configuration is either missing or malformed
    case configuration
    
    /// There was an error building the URL from
    case componentsURL
    
}

public extension Interface {
    
    static func request(
        _ parameters: Parameters,
        _ configuration: ServerConfiguration
    ) throws(RequestError) -> URLRequest {
        return try URLRequest(
            requestParameters: parameters,
            serverConfiguration: configuration
        )
    }
    
}
