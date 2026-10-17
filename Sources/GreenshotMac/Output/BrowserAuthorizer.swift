// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AuthenticationServices
import GreenshotCore
import Network

/// Shows a provider's sign-in page in `ASWebAuthenticationSession` and returns the redirect with the code (upstream
/// opens the system browser and receives the code on its own web page). A custom scheme redirect comes back from the
/// session itself; a loopback redirect (Box allows nothing else) is received by a listener on 127.0.0.1 while the
/// session shows the page.
final class BrowserAuthorizer: NSObject, OAuthAuthorizer, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = BrowserAuthorizer()

    /// The running session, kept alive until it ends.
    @MainActor private var session: ASWebAuthenticationSession?
    /// A window for the session when the app has no other (it is never shown).
    @MainActor private lazy var anchor = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.titled], backing: .buffered, defer: true)

    func authorize(url: URL, redirect: OAuthRedirect) async throws -> URL {
        switch redirect {
        case .customScheme(let callback):
            return try await start(url: url, callbackScheme: callback.scheme, listener: nil)
        case .loopback(let port, let path):
            let listener = try await LoopbackListener.listen(preferredPort: port, path: path)
            var authURL = url
            if listener.port != port {
                authURL = Self.replacingRedirect(in: url, with: OAuthRedirect.loopback(port: listener.port, path: path).url)
            }
            return try await start(url: authURL, callbackScheme: nil, listener: listener)
        }
    }

    /// `redirect_uri` with another port (the preferred one was taken).
    static func replacingRedirect(in url: URL, with redirect: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.map { item in
            item.name == "redirect_uri" ? URLQueryItem(name: item.name, value: redirect.absoluteString) : item
        }
        return components.url ?? url
    }

    @MainActor
    private func start(url: URL, callbackScheme: String?, listener: LoopbackListener?) async throws -> URL {
        session?.cancel()
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            once.continuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                listener?.stop()
                if let callback {
                    once.resume(.success(callback))
                } else if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    once.resume(.failure(error))
                } else {
                    once.resume(.failure(UploadError.cancelled))
                }
            }
            listener?.onCallback = { [weak session] callback in
                once.resume(.success(callback))
                DispatchQueue.main.async { session?.cancel() }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            NSApp.activate()
            if !session.start() {
                listener?.stop()
                once.resume(.failure(UploadError.oauth(String(localized: "The sign-in window could not be opened."))))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain } ?? anchor
        }
    }
}

/// A continuation that can be resumed from several places, once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<URL, Error>?

    func resume(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

/// Answers one HTTP request on 127.0.0.1: the provider's redirect with the code. Anything else (a favicon) gets a 404.
final class LoopbackListener: @unchecked Sendable {
    private(set) var port: UInt16 = 0
    private let path: String
    private let listener: NWListener
    private let queue = DispatchQueue(label: "greenshot.oauth.loopback")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    var onCallback: ((URL) -> Void)?

    /// Listens on the preferred port, or on any free one when it is taken.
    static func listen(preferredPort: UInt16, path: String) async throws -> LoopbackListener {
        do {
            return try await LoopbackListener(port: preferredPort, path: path)
        } catch {
            return try await LoopbackListener(port: 0, path: path)
        }
    }

    private init(port requested: UInt16, path: String) async throws {
        self.path = path
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: requested)!)
        listener = try NWListener(using: parameters)
        let ready = ReadyOnce()
        let listener = self.listener
        port = try await withCheckedThrowingContinuation { continuation in
            ready.continuation = continuation
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: ready.resume(.success(listener.port?.rawValue ?? requested))
                case .failed(let error): ready.resume(.failure(error))
                case .cancelled: ready.resume(.failure(UploadError.cancelled))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let open = connections
        connections = []
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    /// The page the browser shows after the sign-in, in the app's language.
    private static var signedInPage: String {
        let heading = html(String(localized: "Signed in", comment: "Web page shown in the browser after signing in to Box or Dropbox"))
        let text = html(String(localized: "You can close this window and go back to Greenshot."))
        return "<!doctype html><meta charset=utf-8><title>Greenshot</title><body style=\"font-family:-apple-system,sans-serif;margin:3em\">"
            + "<h2>\(heading)</h2><p>\(text)</p>"
    }

    private static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let url = URL(string: "http://127.0.0.1:\(self.port)" + target)
            let matches = url?.path == self.path
            let body = matches ? Self.signedInPage : "Not found"
            let response = "HTTP/1.1 \(matches ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
                if matches, let url { self.onCallback?(url) }
            })
        }
    }
}

private final class ReadyOnce: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<UInt16, Error>?

    func resume(_ result: Result<UInt16, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
