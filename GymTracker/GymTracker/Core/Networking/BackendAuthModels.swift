//
//  BackendAuthModels.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

struct InteractLoginRequest: Encodable {
    let provider = "interact"
    let username: String
    let password: String
}

struct InteractBundlePayload: Codable {
    let apptoken: String
    let accesstoken: String
    let userid: String
    let devtoken: String
    let usertoken: String
}

struct InteractExchangeRequest: Encodable {
    let provider = "interact"
    let bundle: InteractBundlePayload
}

struct BackendAuthUserDTO: Codable {
    let id: String
    let displayName: String?
    let username: String?
}

struct BackendLinkedProviderDTO: Codable {
    let provider: String
    let providerUserId: String
    let displayName: String?
    let username: String?
}

struct BackendIssuedSessionDTO: Codable {
    let accessToken: String
    let expiresAt: String
}

struct BackendCurrentSessionDTO: Codable {
    let id: String
    let expiresAt: String
}

struct BackendAuthSessionResponseDTO: Codable {
    let user: BackendAuthUserDTO
    let session: BackendIssuedSessionDTO
    let linkedProvider: BackendLinkedProviderDTO
}

struct BackendCurrentSessionResponseDTO: Codable {
    let user: BackendAuthUserDTO
    let session: BackendCurrentSessionDTO
    let linkedProvider: BackendLinkedProviderDTO
}

struct BackendMeResponseDTO: Codable {
    let id: String
    let displayName: String?
    let username: String?
}

struct BackendLogoutResponseDTO: Codable {
    let ok: Bool
}
