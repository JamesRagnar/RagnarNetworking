//
//  Interface+Response.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

public enum ResponseError: LocalizedError {
    
    case unknownResponse(URLResponse)
    
    case unknownResponseCase(HTTPURLResponse)
    
    case decoding(InterfaceDecodingError)
    
    case generic(Error)
    
}

public enum InterfaceDecodingError: Error {
    
    /// The response expected a String, but was unable to decode one
    case missingString
    
    /// The response expected raw Data, but
    case missingData
    
    /// There was an issue decoding the data to the expected type
    case jsonDecoder(Error)
    
}

public extension Interface {
    
    static func handle(
        _ response: (data: Data, response: URLResponse)
    ) throws(ResponseError) -> Response {
        guard let httpResponse = response.response as? HTTPURLResponse else {
            throw .unknownResponse(response.response)
        }
        
        guard let responseCase = responseCases[httpResponse.statusCode] else {
            throw .unknownResponseCase(httpResponse)
        }
        
        switch responseCase {
        case .success:
            do {
                return try decode(response: response.data)
            } catch {
                throw .decoding(error)
            }
        case .failure(let error):
            throw .generic(error)
        }
    }
    
    static func decode(response data: Data) throws(InterfaceDecodingError) -> Response {
        if Response.self == String.self {
            guard let response = String(
                data: data,
                encoding: .utf8
            ) as? Response else {
                throw .missingString
            }
            
            return response
        }
        
        if Response.self == Data.self {
            guard let responseData = data as? Response else {
                throw .missingData
            }
            
            return responseData
        }
        
        do {
            return try JSONDecoder().decode(
                Response.self,
                from: data
            )
        } catch {
            throw .jsonDecoder(error)
        }
    }

}

