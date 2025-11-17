//
//  Interface+Response.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// The known possible response error scenarios
public enum ResponseError: LocalizedError {
    
    /// The response type or code could not be determined
    case unknownResponse(Data, URLResponse)
    
    /// The provided Interface does not accept the returned response case
    case unknownResponseCase(Data, HTTPURLResponse)
    
    /// The expected result type could not be decoded for the expected response type
    case decoding(Data, HTTPURLResponse, InterfaceDecodingError)
    
    /// An unhandled error occurred
    case generic(Data, HTTPURLResponse, Error)
    
}

/// Cases where the response type could not be read
public enum InterfaceDecodingError: Error {
    
    /// The response expected a String, but was unable to decode one
    case missingString
    
    /// The response expected raw Data, but was unable to map
    case missingData
    
    /// There was an issue decoding the data to the expected type
    case jsonDecoder(Error)
    
}

public extension Interface {
    
    static func handle(
        _ response: (data: Data, response: URLResponse)
    ) throws(ResponseError) -> Response {
        guard let httpResponse = response.response as? HTTPURLResponse else {
            throw .unknownResponse(
                response.data,
                response.response
            )
        }
        
        guard let responseCase = responseCases[httpResponse.statusCode] else {
            throw .unknownResponseCase(
                response.data,
                httpResponse
            )
        }
        
        switch responseCase {
        case .success:
            do {
                return try decode(response: response.data)
            } catch {
                throw .decoding(
                    response.data,
                    httpResponse,
                    error
                )
            }
        case .failure(let error):
            throw .generic(
                response.data,
                httpResponse,
                error
            )
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

