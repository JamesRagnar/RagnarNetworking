//
//  URLRequest+Authentication.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

public extension URLRequest {

    /// Applies the credential for `scheme` to a request the `RequestBuilder` has finished.
    ///
    /// `URLRequest.init(interfaceRequest:context:)` calls this after the builder returns, so a
    /// builder is never asked to authenticate.
    ///
    /// Query items land first, then header fields, so an authenticator signing in
    /// `headers(for:on:)` reads the final URL. Both sides are validated before anything is
    /// written.
    ///
    /// A request declaring no scheme returns without a lookup and needs no credential.
    ///
    /// - Parameters:
    ///   - scheme: The scheme the request declared, or `nil` for an unauthenticated request
    ///   - context: Supplies the registered `Authenticator` and the credential
    /// - Throws: `RequestError.unregisteredScheme` for a scheme with no authenticator,
    ///   `.missingCredential` when the context carries none, `.undeclaredQueryItemName` for an
    ///   item outside the authenticator's `redactedQueryItemNames`, `.credentialCollision` when
    ///   the request already carries a name the authenticator writes, or
    ///   `.authenticatorAppliedNothing` when it contributed nothing anywhere.
    mutating func applyAuthentication(
        _ scheme: AuthenticationScheme?,
        context: RequestContext
    ) throws(RequestError) {
        guard let scheme else { return }

        let authenticator = try context.authenticator(for: scheme)
        guard let credential = context.credential else { throw .missingCredential(scheme) }

        let components = try credentialComponents()
        let items = try authenticator.queryItems(for: credential, on: components)

        let appliedToURL = try applyCredentialQueryItems(
            items,
            to: components,
            scheme: scheme,
            declaring: authenticator.redactedQueryItemNames
        )

        let fields = try authenticator.headers(for: credential, on: self)

        guard !fields.isEmpty || appliedToURL else {
            throw .authenticatorAppliedNothing(scheme)
        }

        for (name, fieldValue) in fields {
            if value(forHTTPHeaderField: name) != nil {
                throw .credentialCollision(scheme: scheme, name: name)
            }
            setValue(fieldValue, forHTTPHeaderField: name)
        }
    }

    /// The request's URL as components, for an authenticator that reads or signs the URL.
    private func credentialComponents() throws(RequestError) -> URLComponents {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw .invalidRequest(
                description: "The builder returned a request without a valid URL, so the credential could not be applied"
            )
        }

        return components
    }

    /// Appends a credential's query items, rejecting an undeclared name or one the URL already
    /// carries. Leaves the URL untouched when there is nothing to append.
    ///
    /// - Returns: Whether any item was applied.
    private mutating func applyCredentialQueryItems(
        _ items: [URLQueryItem],
        to components: URLComponents,
        scheme: AuthenticationScheme,
        declaring declared: Set<String>
    ) throws(RequestError) -> Bool {
        guard !items.isEmpty else { return false }

        var components = components
        var existing = components.queryItems ?? []

        for item in items {
            guard declared.contains(where: { $0.caseInsensitiveCompare(item.name) == .orderedSame }) else {
                throw .undeclaredQueryItemName(scheme: scheme, name: item.name)
            }

            if existing.contains(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                throw .credentialCollision(scheme: scheme, name: item.name)
            }
        }

        existing.append(contentsOf: items)
        components.queryItems = existing

        guard let url = components.url else { throw .componentsURL }
        self.url = url

        return true
    }

}
