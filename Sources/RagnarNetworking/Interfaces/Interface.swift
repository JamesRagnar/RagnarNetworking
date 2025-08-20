//
//  Interface.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

public protocol Interface {
    
    associatedtype Parameters: RequestParameters

    associatedtype Response: Decodable, Sendable
    
    typealias ResponseCases = [Int: Result<Response.Type, Error>]
        
    static var responseCases: ResponseCases { get }
        
}
