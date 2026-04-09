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
}

//please review interact's code to adapt with tokens
class API_Helper : Observable {
    var apiData = API_Data()

    var baseAPIurl: String {
        apiData.getURL()
    }
    var hostURL: String {
        apiData.getHostURL()
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
        try await executeRequest(route: route, httpMethod: httpMethod, body: nil, additionalHeaders: additionalHeaders)
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

    func url(for route: APIRequestRoute) -> URL? {
        guard var components = URLComponents(string: baseAPIurl) else { return nil }
        components.path += route.path
        if !route.queryItems.isEmpty {
            components.queryItems = route.queryItems
        }
        return components.url
    }

    // Resolves absolute or host-relative media paths against the API host.
    func resolveMediaURL(_ mediaPathOrURL: String) -> URL? {
        guard let baseHostURL = URL(string: hostURL) else { return nil }

        if let absoluteURL = URL(string: mediaPathOrURL), absoluteURL.scheme != nil {
            return absoluteURL
        }

        return URL(string: mediaPathOrURL, relativeTo: baseHostURL)?.absoluteURL
    }

    private func executeRequest<T: Decodable>(
        route: APIRequestRoute,
        httpMethod: APIHTTPMethod,
        body: Data?,
        additionalHeaders: [String: String]
    ) async throws -> T {
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

        return try await executeRequest(request: request)
    }

    private func executeRequest<T: Decodable>(request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIHelperError.invalidResponse
            }

            if 200..<300 ~= httpResponse.statusCode {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                return decodedData
            } else {
                // Log the raw error response for debugging
                if let errorString = String(data: data, encoding: .utf8) {
                    print("Error response string: \(errorString)")
                }

                // Decode the error response
                throw APIHelperError.invalidResponse
            }
        } catch {
            throw error
        }
    }
}
