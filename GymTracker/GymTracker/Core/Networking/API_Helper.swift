//
//  API_Helper.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

/// Local error definitions for API_Helper
enum APIHelperError: Error {
    case invalidResponse
    case missingAccessToken
    case httpError(statusCode: Int, code: String?, message: String?, details: String?)
}

struct APIErrorEnvelope: Decodable {
    struct APIErrorBody: Decodable {
        let code: String?
        let message: String?
        let details: String?
    }

    let error: APIErrorBody
}

struct BackendSessionSnapshot: Codable {
    let accessToken: String
    let expiresAt: Date?
    let accountUserId: String?
}

final class LocalDeviceIdentityStore {
    static let shared = LocalDeviceIdentityStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "gymtracker.device-id."

    private init() {}

    func deviceId(for localUserId: UUID) -> String {
        let key = storageKey(for: localUserId)

        if let existingDeviceId = defaults.string(forKey: key), !existingDeviceId.isEmpty {
            return existingDeviceId
        }

        let generatedDeviceId = UUID().uuidString.lowercased()
        defaults.set(generatedDeviceId, forKey: key)
        return generatedDeviceId
    }

    func clearDeviceId(for localUserId: UUID) {
        defaults.removeObject(forKey: storageKey(for: localUserId))
    }

    private func storageKey(for localUserId: UUID) -> String {
        "\(keyPrefix)\(localUserId.uuidString.lowercased())"
    }
}

final class BackendSessionStore {
    static let shared: BackendSessionStore = BackendSessionStore()

    private let defaults = UserDefaults.standard
    private let activeLocalUserKey = "gymtracker.backend.session.active-local-user"
    private let sessionKeyPrefix = "gymtracker.backend.session."

    private init() {}

    func setActiveLocalUserId(_ localUserId: UUID?) {
        defaults.set(localUserId?.uuidString.lowercased(), forKey: activeLocalUserKey)
    }

    func activeLocalUserId() -> UUID? {
        guard let rawValue = defaults.string(forKey: activeLocalUserKey) else {
            return nil
        }

        return UUID(uuidString: rawValue)
    }

    func loadSession(for localUserId: UUID) -> BackendSessionSnapshot? {
        guard let data = defaults.data(forKey: storageKey(for: localUserId)) else { return nil }
        return try? JSONDecoder().decode(BackendSessionSnapshot.self, from: data)
    }

    func saveSession(_ snapshot: BackendSessionSnapshot, for localUserId: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey(for: localUserId))
        setActiveLocalUserId(localUserId)
    }

    func clearSession(for localUserId: UUID) {
        defaults.removeObject(forKey: storageKey(for: localUserId))

        if activeLocalUserId() == localUserId {
            defaults.removeObject(forKey: activeLocalUserKey)
        }
    }

    var accessToken: String? {
        guard let localUserId = activeLocalUserId() else { return nil }
        return loadSession(for: localUserId)?.accessToken
    }

    private func storageKey(for localUserId: UUID) -> String {
        "\(sessionKeyPrefix)\(localUserId.uuidString.lowercased())"
    }
}

//please review interact's code to adapt with tokens
class API_Helper : Observable {
    var apiData = API_Data()

    var baseAPIurl: String {
        apiData.baseURLString(for: .backend)
    }
    var hostURL: String {
        apiData.hostURLString(for: .backend)
    }
    var exerciseDBBaseURL: String {
        apiData.baseURLString(for: .exerciseDB)
    }
    var exerciseDBHostURL: String {
        apiData.hostURLString(for: .exerciseDB)
    }
    var errorTime:Date = Date()
    
    init() {
        print("init API_Helper")
    }
    
    func asyncRequestData<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .GET,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        try await executeRequest(route: route, httpMethod: httpMethod, body: nil, additionalHeaders: additionalHeaders)
    }

    func asyncRequestListData<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .GET,
        additionalHeaders: [String: String] = [:]
    ) async throws -> ListResponse<T> {
        try await executeRequestList(route: route, httpMethod: httpMethod, body: nil, additionalHeaders: additionalHeaders)
    }

    func asyncAuthorizedRequestData<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .GET,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        try await executeRequest(
            route: route,
            httpMethod: httpMethod,
            body: nil,
            additionalHeaders: authorizedHeaders(merging: additionalHeaders)
        )
    }

    func asyncAuthorizedRequestListData<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .GET,
        additionalHeaders: [String: String] = [:]
    ) async throws -> ListResponse<T> {
        try await executeRequestList(
            route: route,
            httpMethod: httpMethod,
            body: nil,
            additionalHeaders: authorizedHeaders(merging: additionalHeaders)
        )
    }

    func asyncRequestData<T: Decodable, Body: Encodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .POST,
        body: Body,
        additionalHeaders: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await executeRequest(route: route, httpMethod: httpMethod, body: bodyData, additionalHeaders: additionalHeaders)
    }

    func asyncAuthorizedRequestData<T: Decodable, Body: Encodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .POST,
        body: Body,
        additionalHeaders: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await executeRequest(
            route: route,
            httpMethod: httpMethod,
            body: bodyData,
            additionalHeaders: authorizedHeaders(merging: additionalHeaders)
        )
    }

    func asyncRequestData<T: Decodable>(
        urlString: String,
        errorType: String = "normal",
        httpMethod: String = "GET"
    ) async throws -> T {
        //create the new url
        guard let url = URL(string: urlString) else {
            throw APIHelperError.invalidResponse
        }

        //create a new urlRequest passing the url
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Execute the request
        return try await executeRequest(request: request)
    }

    func asyncRequestRawData(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .GET,
        additionalHeaders: [String: String] = [:]
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let request = try makeRequest(
            route: route,
            httpMethod: httpMethod,
            body: nil,
            additionalHeaders: additionalHeaders
        )
        return try await executeRawRequest(request: request)
    }

    func asyncAuthorizedRequestRawData(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod = .GET,
        additionalHeaders: [String: String] = [:]
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let request = try makeRequest(
            route: route,
            httpMethod: httpMethod,
            body: nil,
            additionalHeaders: authorizedHeaders(merging: additionalHeaders)
        )
        return try await executeRawRequest(request: request)
    }

    func url(for route: APIRequestRoute) -> URL? {
        guard var components = URLComponents(string: apiData.baseURLString(for: route.baseURLKind)) else { return nil }
        components.path += route.path
        if !route.queryItems.isEmpty {
            components.queryItems = route.queryItems
        }
        return components.url
    }

    // Resolves absolute or host-relative media paths against the API host.
    func resolveMediaURL(
        _ mediaPathOrURL: String,
        baseURLKind: APIBaseURLKind = .backend
    ) -> URL? {
        guard let baseHostURL = URL(string: apiData.hostURLString(for: baseURLKind)) else { return nil }

        if let absoluteURL = URL(string: mediaPathOrURL), absoluteURL.scheme != nil {
            return absoluteURL
        }

        return URL(string: mediaPathOrURL, relativeTo: baseHostURL)?.absoluteURL
    }

    func authorizedHeaders(merging additionalHeaders: [String: String] = [:]) throws -> [String: String] {
        guard let accessToken = BackendSessionStore.shared.accessToken else {
            throw APIHelperError.missingAccessToken
        }

        var headers = additionalHeaders
        headers["Authorization"] = "Bearer \(accessToken)"
        if let activeLocalUserId = BackendSessionStore.shared.activeLocalUserId() {
            headers["X-GymTracker-Device-Id"] = LocalDeviceIdentityStore.shared.deviceId(for: activeLocalUserId)
        }
        headers["X-GymTracker-Platform"] = "ios"
        return headers
    }

    private func executeRequest<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod,
        body: Data?,
        additionalHeaders: [String: String]
    ) async throws -> T {
        let request = try makeRequest(
            route: route,
            httpMethod: httpMethod,
            body: body,
            additionalHeaders: additionalHeaders
        )
        return try await executeRequest(request: request)
    }

    private func executeRequestList<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod,
        body: Data?,
        additionalHeaders: [String: String]
    ) async throws -> ListResponse<T> {
        let request = try makeRequest(
            route: route,
            httpMethod: httpMethod,
            body: body,
            additionalHeaders: additionalHeaders
        )
        let (data, response) = try await executeRawRequest(request: request)
        guard 200..<300 ~= response.statusCode else {
            throw parseHTTPError(data: data, response: response)
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ListEnvelope<T>.self, from: data)
        return ListResponse(items: envelope.items)
    }

    private func makeRequest(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod,
        body: Data?,
        additionalHeaders: [String: String]
    ) throws -> URLRequest {
        guard let url = url(for: route) else {
            throw APIHelperError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        return request
    }

    private func executeRequest<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await executeRawRequest(request: request)

        if 200..<300 ~= response.statusCode {
            let decodedData = try JSONDecoder().decode(T.self, from: data)
            return decodedData
        }
        throw parseHTTPError(data: data, response: response)
    }

    private func executeRawRequest(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIHelperError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func parseHTTPError(data: Data, response: HTTPURLResponse) -> APIHelperError {
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let errorString = String(data: data, encoding: .utf8)

        return .httpError(
            statusCode: response.statusCode,
            code: envelope?.error.code,
            message: envelope?.error.message,
            details: envelope?.error.details ?? errorString
        )
    }
}
