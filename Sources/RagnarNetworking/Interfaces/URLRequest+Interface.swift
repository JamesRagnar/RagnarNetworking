//
//  URLRequest+Interface.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

// MARK: - Request Error

/// Errors that can occur during URLRequest construction.
public enum RequestError: Error {

    /// The server configuration could not be parsed or is malformed
    case configuration

    /// The request requires authentication but no token was provided
    case authentication

    /// The URL components could not be assembled into a valid URL
    case componentsURL

    /// The request body could not be encoded
    case encoding(underlying: Error)

}

// MARK: - URLRequest Construction

public extension URLRequest {

    /// Convenience initializer that constructs a URLRequest from an Interface type.
    ///
    /// This is a type-safe wrapper around the `RequestParameters` initializer.
    ///
    /// - Parameters:
    ///   - interface: The interface type (used for type inference)
    ///   - parameters: The Interface parameters defining the request
    ///   - configuration: The server configuration with base URL and auth token
    /// - Throws: `RequestError` if the request cannot be constructed
    init<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) throws(RequestError) {
        try self.init(
            requestParameters: parameters,
            serverConfiguration: configuration
        )
    }

    /// Constructs a URLRequest from Interface parameters and server configuration.
    ///
    /// This initializer builds a complete URLRequest by combining the base server configuration
    /// with request-specific parameters. It handles authentication, query parameters, headers,
    /// and body data according to the Interface specification.
    ///
    /// - Parameters:
    ///   - requestParameters: The Interface parameters defining the request
    ///   - serverConfiguration: The server configuration with base URL and auth token
    /// - Throws: `RequestError` if the request cannot be constructed
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
        
        // MARK: Body
        
        let bodyResult = try Self.makeBody(requestParameters.body)
        request.httpBody = bodyResult.data
        
        if currentHeaderFields["Content-Type"] == nil,
           let contentType = bodyResult.contentType {
            currentHeaderFields["Content-Type"] = contentType
        }
        
        request.allHTTPHeaderFields = currentHeaderFields
        
        self = request
    }

}

// MARK: - Body Construction

private extension URLRequest {

    struct BodyResult {
        let data: Data?
        let contentType: String?
    }

    static func makeBody(_ body: RequestBody?) throws(RequestError) -> BodyResult {
        guard let body else {
            return BodyResult(data: nil, contentType: nil)
        }

        switch body {
        case .data(let data):
            return BodyResult(data: data, contentType: nil)
        case .json(let encodable):
            do {
                let data = try JSONEncoder().encode(encodable)
                return BodyResult(
                    data: data,
                    contentType: "application/json; charset=utf-8"
                )
            } catch {
                throw .encoding(underlying: error)
            }
        case .formURLEncoded(let fields):
            return BodyResult(
                data: formURLEncodedBody(fields),
                contentType: "application/x-www-form-urlencoded; charset=utf-8"
            )
        case .text(let text, let encoding):
            guard let data = text.data(using: encoding) else {
                throw .encoding(
                    underlying: EncodingError.invalidValue(
                        text,
                        EncodingError.Context(
                            codingPath: [],
                            debugDescription: "Unable to encode text with \(encoding)."
                        )
                    )
                )
            }
            let charset = charsetName(for: encoding)
            let contentType = charset.map { "text/plain; charset=\($0)" } ?? "text/plain"
            return BodyResult(
                data: data,
                contentType: contentType
            )
        }
    }

}

private extension URLRequest {

    static func charsetName(for encoding: String.Encoding) -> String? {
        switch encoding {
        case .utf8: "utf-8"
        case .ascii: "us-ascii"
        case .isoLatin1: "iso-8859-1"
        case .utf16: "utf-16"
        case .utf16LittleEndian: "utf-16le"
        case .utf16BigEndian: "utf-16be"
        case .utf32: "utf-32"
        case .utf32LittleEndian: "utf-32le"
        case .utf32BigEndian: "utf-32be"
        default: nil
        }
    }

}

// MARK: - Form URL Encoding

private func formURLEncodedBody(_ fields: [String: String]) -> Data {
    guard !fields.isEmpty else {
        return Data()
    }

    var components = URLComponents()
    components.queryItems = fields
        .map { URLQueryItem(name: $0.key, value: $0.value) }
        .sorted { $0.name < $1.name }

    let query = components.percentEncodedQuery ?? ""
    return Data(query.utf8)
}
