// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

// OAuth 2 with PKCE for Box and Dropbox: the logic of upstream `Greenshot.Base/Core/OAuth/OAuth2Helper.cs`. Upstream
// ships its own client IDs and a web page that receives the code; this port can't reuse them, so every user
// registers an app of their own and the code comes back to the app itself (a custom URL scheme, or a loopback
// address for Box, which allows no custom schemes).

/// RFC 7636.
public enum PKCE {
    /// 64 characters from the unreserved set.
    public static func verifier(length: Int = 64) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// `BASE64URL(SHA256(verifier))`.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Where the provider sends the browser with the code.
public enum OAuthRedirect: Equatable, Sendable {
    /// e.g. `greenshotmac://oauth/dropbox`: the system hands the URL to the app.
    case customScheme(URL)
    /// `http://127.0.0.1:{port}{path}`: the app listens there while signing in (Box allows only https or loopback).
    case loopback(port: UInt16, path: String)

    public var url: URL {
        switch self {
        case .customScheme(let url): return url
        case .loopback(let port, let path): return URL(string: "http://127.0.0.1:\(port)\(path)")!
        }
    }

    /// The same redirect on another port (when the preferred one is taken).
    public func onPort(_ port: UInt16) -> OAuthRedirect {
        if case .loopback(_, let path) = self { return .loopback(port: port, path: path) }
        return self
    }
}

public struct OAuthProvider: Equatable, Sendable {
    public var name: String
    public var authorizationURL: URL
    public var tokenURL: URL
    public var redirect: OAuthRedirect
    /// Extra query items of the authorization URL.
    public var extraAuthorizationParameters: [String: String]
    /// Where the user registers an app (shown in Settings).
    public var developerConsoleURL: URL

    public init(name: String, authorizationURL: URL, tokenURL: URL, redirect: OAuthRedirect,
                extraAuthorizationParameters: [String: String] = [:], developerConsoleURL: URL) {
        self.name = name
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.redirect = redirect
        self.extraAuthorizationParameters = extraAuthorizationParameters
        self.developerConsoleURL = developerConsoleURL
    }

    public static let callbackScheme = "greenshotmac"
    public static let boxLoopbackPort: UInt16 = 52398

    /// Box: a "Custom App" with "User Authentication (OAuth 2.0)"; needs the client secret too (Box documents no
    /// secretless flow), the PKCE values are sent as well. Redirect URI to register: `http://127.0.0.1:52398/box`.
    public static let box = OAuthProvider(
        name: "Box",
        authorizationURL: URL(string: "https://account.box.com/api/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.box.com/oauth2/token")!,
        redirect: .loopback(port: boxLoopbackPort, path: "/box"),
        developerConsoleURL: URL(string: "https://app.box.com/developers/console")!)

    /// Dropbox: a "Scoped access" app with the `files.content.write`, `sharing.write` and `sharing.read`
    /// permissions and the redirect URI `greenshotmac://oauth/dropbox`; PKCE, no secret. `token_access_type=offline`
    /// asks for a refresh token.
    public static let dropbox = OAuthProvider(
        name: "Dropbox",
        authorizationURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.dropboxapi.com/oauth2/token")!,
        redirect: .customScheme(URL(string: "\(callbackScheme)://oauth/dropbox")!),
        extraAuthorizationParameters: ["token_access_type": "offline"],
        developerConsoleURL: URL(string: "https://www.dropbox.com/developers/apps")!)
}

/// What the token endpoint gave, as stored in the secret store (JSON).
public struct OAuthTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Usable for at least another minute (a token without an expiry counts as usable).
    public func isUsable(at now: Date, margin: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) > margin
    }

    /// The token endpoint's JSON. Dropbox answers a refresh without a refresh token: `previous` keeps it.
    public static func parse(json data: Data, now: Date, previous: OAuthTokens? = nil) throws -> OAuthTokens {
        let object = try HTTPSupport.json(data)
        guard let access = object["access_token"] as? String, !access.isEmpty else {
            throw UploadError.unexpectedResponse("no access token in the answer")
        }
        let expires = (object["expires_in"] as? NSNumber)?.doubleValue
        return OAuthTokens(accessToken: access,
                           refreshToken: object["refresh_token"] as? String ?? previous?.refreshToken,
                           expiresAt: expires.map { now.addingTimeInterval($0) })
    }
}

/// The requests and URLs of the authorization code flow.
public enum OAuthFlow {
    public static func authorizationURL(provider: OAuthProvider, clientID: String, redirect: OAuthRedirect,
                                        state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: provider.authorizationURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect.url.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        for key in provider.extraAuthorizationParameters.keys.sorted() {
            items.append(URLQueryItem(name: key, value: provider.extraAuthorizationParameters[key]))
        }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url!
    }

    /// The code in the callback URL; the state has to be the one sent.
    public static func authorizationCode(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            if error == "access_denied" { throw UploadError.cancelled }
            throw UploadError.oauth(value("error_description") ?? error)
        }
        guard value("state") == expectedState else { throw UploadError.oauth("The sign-in answer did not match the request (state).") }
        guard let code = value("code"), !code.isEmpty else { throw UploadError.oauth("The sign-in answer had no code.") }
        return code
    }

    public static func tokenRequest(provider: OAuthProvider, clientID: String, clientSecret: String?, code: String,
                                    codeVerifier: String, redirect: OAuthRedirect) -> URLRequest {
        var fields = [("grant_type", "authorization_code"), ("code", code), ("client_id", clientID),
                      ("redirect_uri", redirect.url.absoluteString), ("code_verifier", codeVerifier)]
        if let clientSecret, !clientSecret.isEmpty { fields.append(("client_secret", clientSecret)) }
        return formRequest(provider.tokenURL, fields)
    }

    public static func refreshRequest(provider: OAuthProvider, clientID: String, clientSecret: String?, refreshToken: String) -> URLRequest {
        var fields = [("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)]
        if let clientSecret, !clientSecret.isEmpty { fields.append(("client_secret", clientSecret)) }
        return formRequest(provider.tokenURL, fields)
    }

    private static func formRequest(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = HTTPSupport.formBody(fields)
        return request
    }
}

/// Shows the sign-in page and returns the URL the provider redirected to (with the code). The app does this with
/// `ASWebAuthenticationSession`; tests answer at once.
public protocol OAuthAuthorizer: Sendable {
    func authorize(url: URL, redirect: OAuthRedirect) async throws -> URL
}

/// One account at one provider: keeps the tokens in the secret store, refreshes them, signs in when needed.
public struct OAuthClient: Sendable {
    public let provider: OAuthProvider
    public let clientID: String
    public let clientSecret: String?
    public let store: SecretStore
    /// The key of the tokens in the store.
    public let storeKey: String
    public let http: HTTPClient
    let now: @Sendable () -> Date

    public init(provider: OAuthProvider, clientID: String, clientSecret: String? = nil, store: SecretStore,
                storeKey: String, http: HTTPClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.clientID = clientID.trimmingCharacters(in: .whitespaces)
        self.clientSecret = clientSecret
        self.store = store
        self.storeKey = storeKey
        self.http = http
        self.now = now
    }

    public var tokens: OAuthTokens? {
        guard let text = try? store.secret(for: storeKey), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public var isSignedIn: Bool { tokens != nil }

    public func signOut() throws {
        try store.setSecret(nil, for: storeKey)
    }

    /// Forgets the access token (after the server rejected it) but keeps the refresh token.
    public func invalidateAccessToken() throws {
        guard var current = tokens else { return }
        current.expiresAt = .distantPast
        try save(current)
    }

    /// A usable access token: the stored one, a refreshed one, or (with an authorizer) a new sign-in.
    public func accessToken(authorizer: OAuthAuthorizer?) async throws -> String {
        guard !clientID.isEmpty else { throw UploadError.notConfigured("The \(provider.name) app key") }
        if let current = tokens {
            if current.isUsable(at: now()) { return current.accessToken }
            if let refresh = current.refreshToken {
                let request = OAuthFlow.refreshRequest(provider: provider, clientID: clientID, clientSecret: clientSecret, refreshToken: refresh)
                do {
                    let data = try await HTTPSupport.send(request, with: http)
                    let refreshed = try OAuthTokens.parse(json: data, now: now(), previous: current)
                    try save(refreshed)
                    return refreshed.accessToken
                } catch UploadError.http(let status, _) where status == 400 || status == 401 {
                    // The refresh token is no longer good: sign in again below.
                    try? signOut()
                }
            }
        }
        guard let authorizer else { throw UploadError.notSignedIn(provider.name) }
        return try await signIn(with: authorizer).accessToken
    }

    /// The whole flow: PKCE values, the sign-in page, the code, the tokens (stored).
    @discardableResult
    public func signIn(with authorizer: OAuthAuthorizer) async throws -> OAuthTokens {
        guard !clientID.isEmpty else { throw UploadError.notConfigured("The \(provider.name) app key") }
        let verifier = PKCE.verifier()
        let state = PKCE.verifier(length: 24)
        let url = OAuthFlow.authorizationURL(provider: provider, clientID: clientID, redirect: provider.redirect,
                                             state: state, codeChallenge: PKCE.challenge(for: verifier))
        let callback = try await authorizer.authorize(url: url, redirect: provider.redirect)
        let code = try OAuthFlow.authorizationCode(fromCallback: callback, expectedState: state)
        // The authorizer may have had to listen on another port; the token request names the URL it really used.
        let usedRedirect = Self.redirectUsed(for: callback, preferred: provider.redirect)
        let request = OAuthFlow.tokenRequest(provider: provider, clientID: clientID, clientSecret: clientSecret,
                                             code: code, codeVerifier: verifier, redirect: usedRedirect)
        let tokens = try OAuthTokens.parse(json: try await HTTPSupport.send(request, with: http), now: now())
        try save(tokens)
        return tokens
    }

    static func redirectUsed(for callback: URL, preferred: OAuthRedirect) -> OAuthRedirect {
        if case .loopback = preferred, let port = callback.port, port > 0 { return preferred.onPort(UInt16(port)) }
        return preferred
    }

    func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try store.setSecret(String(decoding: data, as: UTF8.self), for: storeKey)
    }
}
