//
//  ServerConfigurationProvider.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

public protocol ServerConfigurationProvider: AnyObject {
    
    var serverConfiguration: ServerConfiguration? { get }
    
}
