//
//  API_Route.swift
//  GymTracker
//
//  Created by Copilot on 2026-04-09.
//

import Foundation

enum APIHTTPMethod: String {
    case GET
    case POST
    case PATCH
    case PUT
    case DELETE
}

protocol APIRequestRoute {
    var path: String { get }
    var queryItems: [URLQueryItem] { get }
}

extension APIRequestRoute {
    var queryItems: [URLQueryItem] { [] }
}

enum APIRoute: APIRequestRoute {
    case exercises
    case exercise(id: String)

    var path: String {
        switch self {
        case .exercises:
            return "/exercises"
        case .exercise(let id):
            return "/exercises/\(id)"
        }
    }
}