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
    case authInteractLogin
    case authInteractExchange
    case authSession
    case authLogout
    case me
    case exercises
    case exercise(id: String)

    var path: String {
        switch self {
        case .authInteractLogin:
            return "/auth/providers/interact/login"
        case .authInteractExchange:
            return "/auth/providers/interact/exchange"
        case .authSession:
            return "/auth/session"
        case .authLogout:
            return "/auth/logout"
        case .me:
            return "/me"
        case .exercises:
            return "/exercises"
        case .exercise(let id):
            return "/exercises/\(id)"
        }
    }
}
