//
//  URLRequest+Interface.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

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
            currentQueryItems.append(
                URLQueryItem(
                    name: "token",
                    value: serverConfiguration.authToken
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
            currentHeaderFields["Authorization"] = "Bearer \(serverConfiguration.authToken)"
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
