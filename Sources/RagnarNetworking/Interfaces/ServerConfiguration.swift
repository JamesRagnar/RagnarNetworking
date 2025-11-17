//
//  ServerConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

public struct ServerConfiguration {
    
    let url: URL
    
    let authToken: String?
    
    public init(
        url: URL,
        authToken: String? = nil
    ) {
        self.url = url
        self.authToken = authToken
    }
    
}

extension ServerConfiguration: Sendable {}
