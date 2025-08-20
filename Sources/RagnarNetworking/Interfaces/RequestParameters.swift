//
//  RequestParameters.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

public protocol RequestParameters: Sendable {
        
    var method: RequestMethod { get }
    
    var path: String { get }
    
    var queryItems: [String: String]? { get }
    
    var headers: [String: String]? { get }
    
    var body: Data? { get }

    var authentication: AuthenticationType { get }

}

public enum AuthenticationType: Sendable {
    
    /// Unauthenticated request
    case none
    
    /// Authentication token included in request headers as `Authorization: Bearer <token>`
    case bearer
    
    /// Authentication token included in query parameters as `?token=<token>`
    case url

}

public enum RequestMethod: String, Sendable {
    
        case get = "GET"
    
        case post = "POST"
    
        case put = "PUT"
    
        case head = "HEAD"
    
        case delete = "DELETE"
    
        case patch = "PATCH"
    
        case options = "OPTIONS"
    
        case connect = "CONNECT"
    
        case trace = "TRACE"
    
}
