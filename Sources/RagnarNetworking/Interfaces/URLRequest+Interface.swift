//
//  URLRequest+Interface.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

public enum RequestError: Error {
    
    /// The Server Configuration is either missing or malformed
    case configuration
    
    /// The Interface indicates a required authentication type that is missing
    case authentication
    
    /// There was an error building the URL from
    case componentsURL
    
}

public extension URLRequest {
    
    init(
        requestParameters: RequestParameters,
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) {
        guard var components = URLComponents(
            url: serverConfiguration.url,
            resolvingAgainstBaseURL: false
        ) else {
            throw .configuration
        }
        
        // MARK: Path
        
        components.path = requestParameters.path
        
        // MARK: Query Items
        
        var currentQueryItems = components.queryItems ?? []
        
        if case .url = requestParameters.authentication {
            guard let token = serverConfiguration.authToken else {
                throw .authentication
            }
            
            currentQueryItems.append(
                URLQueryItem(
                    name: "token",
                    value: token
                )
            )
        }
        
        let newQueryItems = requestParameters.queryItems?.map {
            URLQueryItem(
                name: $0.key,
                value: $0.value
            )
        }
        
        if let newQueryItems {
            currentQueryItems.append(contentsOf: newQueryItems)
        }
        
        components.queryItems = currentQueryItems
        
        guard let url = components.url else {
            throw .componentsURL
        }

        var request = URLRequest(url: url)
        
        // MARK: Method
        
        request.httpMethod = requestParameters.method.rawValue
        
        // MARK: Headers
        
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        var currentHeaderFields = request.allHTTPHeaderFields ?? [:]
        
        if case .bearer = requestParameters.authentication {
            guard let token = serverConfiguration.authToken else {
                throw .authentication
            }
            
            currentHeaderFields["Authorization"] = "Bearer \(token)"
        }
        
        if let newHeaderFields = requestParameters.headers {
            currentHeaderFields.merge(
                newHeaderFields,
                uniquingKeysWith: { $1 }
            )
        }
        
        request.allHTTPHeaderFields = currentHeaderFields
        
        // MARK: Body
        
        if let body = requestParameters.body {
            request.httpBody = body
        }
        
        self = request
    }

}
