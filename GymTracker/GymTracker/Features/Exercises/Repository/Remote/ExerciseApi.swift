//
//  ExerciseAPI.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

enum ExerciseCatalogFetchResult {
    case notModified(etag: String?)
    case catalog(items: [ExerciseDTO], etag: String?)
}

protocol ExerciseCatalogSource {
    var routeDescription: String { get }
    func fetchCatalog(ifNoneMatch: String?) async throws -> ExerciseCatalogFetchResult
}

protocol UserExerciseSource {
    var routeDescription: String { get }
    func fetchUserExercises() async throws -> [GymTrackerExerciseDTO]
}

protocol CatalogOverlaySource {
    var routeDescription: String { get }
    func fetchCatalogOverlays(updatedAfter: Date?) async throws -> [GymTrackerCatalogOverlayDTO]
}

final class PublicExerciseDBSource: ExerciseCatalogSource {
    private let apiHelper: API_Helper

    init(apiHelper: API_Helper = API_Helper()) {
        self.apiHelper = apiHelper
    }

    var routeDescription: String {
        "/v1/exercisedb"
    }

    func fetchCatalog(ifNoneMatch: String?) async throws -> ExerciseCatalogFetchResult {
        var headers: [String: String] = [:]
        if let ifNoneMatch, !ifNoneMatch.isEmpty {
            headers["If-None-Match"] = ifNoneMatch
        }

        let result = try await apiHelper.asyncRequestRawData(
            route: APIRoute.exerciseDB,
            additionalHeaders: headers
        )
        let response = result.response
        let etag = response.value(forHTTPHeaderField: "ETag")

        if response.statusCode == 304 {
            return .notModified(etag: etag)
        }

        guard 200..<300 ~= response.statusCode else {
            let body = String(data: result.data, encoding: .utf8)
            throw APIHelperError.httpError(
                statusCode: response.statusCode,
                code: nil,
                message: "ExerciseDB request failed.",
                details: body
            )
        }

        let catalog = try ArrayOrEnvelopeDecoder.decode([ExerciseDTO].self, from: result.data)
        return .catalog(items: catalog, etag: etag)
    }
}

final class ExerciseRouteResolver {
    private let catalogSourceInstance: any ExerciseCatalogSource
    private let userSourceInstance: any UserExerciseSource
    private let overlaySourceInstance: any CatalogOverlaySource

    init(
        catalogSource: any ExerciseCatalogSource = PublicExerciseDBSource(),
        userSource: any UserExerciseSource = AuthenticatedUserExerciseSource(),
        overlaySource: any CatalogOverlaySource = AuthenticatedCatalogOverlaySource()
    ) {
        self.catalogSourceInstance = catalogSource
        self.userSourceInstance = userSource
        self.overlaySourceInstance = overlaySource
    }

    func catalogSource(for authState: Bool) -> any ExerciseCatalogSource {
        // Catalog fetches are always public-route first.
        _ = authState
        return catalogSourceInstance
    }

    func userSource(for authState: Bool) -> (any UserExerciseSource)? {
        authState ? userSourceInstance : nil
    }

    func overlaySource(for authState: Bool) -> (any CatalogOverlaySource)? {
        authState ? overlaySourceInstance : nil
    }
}

struct GymTrackerExerciseDTO: Identifiable, Codable {
    let id: String
    let source: String
    let name: String
    let type: String
    let aliases: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String?
    let category: String?
    let instructions: [String]
    let images: [String]
    let isUserCreated: Bool
    let isArchived: Bool
    let isEditable: Bool
    let isDeletable: Bool
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct GymTrackerCatalogOverlayDTO: Identifiable, Codable {
    let npId: String
    let aliases: [String]
    let hidden: Bool
    let updatedAt: String

    var id: String { npId }
}
