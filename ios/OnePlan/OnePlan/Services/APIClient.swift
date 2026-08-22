//
//  APIClient.swift
//  OnePlan
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

extension Notification.Name {
    nonisolated(unsafe) static let authSessionExpired = Notification.Name(
        "authSessionExpired"
    )
}

enum APIEnvironment {
    case local
    case dev
    case prod

    /// Where a Debug build looks for the server.
    ///
    /// Overridable from Info.plist because "localhost" only works in the
    /// simulator, which shares the Mac's loopback. On a real device localhost is
    /// the phone itself, so testing there needs the Mac's address on the LAN.
    /// Set LocalAPIHost to something like http://192.168.1.10:3000 and both the
    /// simulator and the device reach the same server.
    static var localHost: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "LocalAPIHost") as? String
        if let configured, !configured.isEmpty { return configured }
        return "http://localhost:3000"
    }

    var baseURL: String {
        switch self {
        case .local: return APIEnvironment.localHost
        case .dev: return "https://dev-api.oneplan.space"
        case .prod: return "https://api.oneplan.space"
        }
    }

    var serverURL: URL {
        URL(string: baseURL)!
    }

    func webSocketURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    static var current: APIEnvironment {
        #if DEBUG
            return .local
        #elseif DEV
            return .dev
        #else
            return .prod
        #endif
    }
}

enum APIClient {
    private static var cachedToken: String?
    private static var cachedClient: Client?
    static var shared: Client {
        let currentToken = AuthTokenStore.shared.accessToken
        if let client = cachedClient, cachedToken == currentToken {
            return client
        }
        let config = URLSessionConfiguration.default
        if let token = currentToken {
            config.httpAdditionalHeaders = ["Authorization": "Bearer \(token)"]
        }
        let client = Client(
            serverURL: APIEnvironment.current.serverURL,
            transport: URLSessionTransport(
                configuration: .init(session: URLSession(configuration: config))
            ),
            middlewares: [AuthStatusMiddleware(), AnalyticsHeadersMiddleware()]
        )
        cachedClient = client
        cachedToken = currentToken
        return client
    }
}

/// Adds `X-Session-Id` and `X-Anonymous-Id` headers from `AnalyticsClient`
/// to every outgoing request so the server can attribute server-emitted
/// analytics events to the same session.
private struct AnalyticsHeadersMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next:
            @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (
                HTTPResponse, HTTPBody?
            )
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var mutableRequest = request
        let (sessionId, anonymousId) = await MainActor.run {
            (AnalyticsClient.shared.currentSessionId, AnalyticsClient.shared.anonymousId)
        }
        if let sessionId, let field = HTTPField.Name("X-Session-Id") {
            mutableRequest.headerFields[field] = sessionId
        }
        if let anonymousId, let field = HTTPField.Name("X-Anonymous-Id") {
            mutableRequest.headerFields[field] = anonymousId
        }
        return try await next(mutableRequest, body, baseURL)
    }
}

/// Intercepts API responses and posts a notification when a 401 is received,
/// so AuthService can force the user back to LoginView.
private struct AuthStatusMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next:
            @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (
                HTTPResponse, HTTPBody?
            )
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        if response.status.code == 401 {
            NotificationCenter.default.post(
                name: .authSessionExpired,
                object: nil
            )
        }
        return (response, responseBody)
    }
}
