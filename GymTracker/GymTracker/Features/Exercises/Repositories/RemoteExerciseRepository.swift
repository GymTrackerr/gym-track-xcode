//
//  RemoteExerciseRepository.swift
//  GymTracker
//
//  Created by Codex on 2026-04-15.
//

import Foundation

private struct ExerciseListRoute: APIRequestRoute {
    let queryItems: [URLQueryItem]
    var path: String { "/exercises" }
}

private struct ExerciseRestoreRoute: APIRequestRoute {
    let exerciseId: String
    var path: String { "/exercises/\(exerciseId)/restore" }
}

private struct CatalogOverlayListRoute: APIRequestRoute {
    let queryItems: [URLQueryItem]
    var path: String { "/exercises/catalog-overlays" }
}

private struct RemoteExerciseUpsertBody: Encodable {
    let name: String
    let type: String
    let aliases: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String?
    let category: String?
    let instructions: [String]
    let images: [String]
    let isArchived: Bool
    let baseUpdatedAt: String?
}

private struct RemoteCatalogOverlayUpdateBody: Encodable {
    let aliases: [String]
    let isArchived: Bool
}

final class RemoteExerciseRepository {
    private let apiHelper: API_Helper
    private let iso8601Formatter: ISO8601DateFormatter

    init(apiHelper: API_Helper = API_Helper()) {
        self.apiHelper = apiHelper
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601Formatter = formatter
    }

    func fetchUserExercises(
        updatedAfter: Date? = nil,
        deletedAfter: Date? = nil,
        includeDeleted: Bool = true
    ) async throws -> [GymTrackerExerciseDTO] {
        var queryItems = [URLQueryItem(name: "source", value: "user")]
        if includeDeleted {
            queryItems.append(URLQueryItem(name: "includeDeleted", value: "true"))
        }
        if let updatedAfter {
            queryItems.append(
                URLQueryItem(
                    name: "updatedAfter",
                    value: iso8601Formatter.string(from: updatedAfter)
                )
            )
        }
        if let deletedAfter {
            queryItems.append(
                URLQueryItem(
                    name: "deletedAfter",
                    value: iso8601Formatter.string(from: deletedAfter)
                )
            )
        }

        let response: ListResponse<GymTrackerExerciseDTO> =
            try await apiHelper.asyncAuthorizedRequestListData(
                route: ExerciseListRoute(queryItems: queryItems)
            )
        return response.items
    }

    func fetchCatalogOverlays(updatedAfter: Date? = nil) async throws -> [GymTrackerCatalogOverlayDTO] {
        var queryItems: [URLQueryItem] = []
        if let updatedAfter {
            queryItems.append(
                URLQueryItem(
                    name: "updatedAfter",
                    value: iso8601Formatter.string(from: updatedAfter)
                )
            )
        }

        let response: ListResponse<GymTrackerCatalogOverlayDTO> =
            try await apiHelper.asyncAuthorizedRequestListData(
                route: CatalogOverlayListRoute(queryItems: queryItems)
            )
        return response.items
    }

    func upsertUserExercise(_ exercise: Exercise) async throws -> GymTrackerExerciseDTO {
        let body = RemoteExerciseUpsertBody(
            name: exercise.name,
            type: exercise.exerciseType.name.lowercased(),
            aliases: exercise.aliases ?? [],
            primaryMuscles: exercise.primary_muscles ?? [],
            secondaryMuscles: exercise.secondary_muscles ?? [],
            equipment: exercise.equipment,
            category: exercise.category,
            instructions: exercise.instructions ?? [],
            images: exercise.images ?? [],
            isArchived: exercise.soft_deleted || exercise.isArchived,
            baseUpdatedAt: nil
        )

        return try await apiHelper.asyncAuthorizedRequestData(
            route: APIRoute.exercise(id: exercise.id.uuidString.lowercased()),
            httpMethod: .PUT,
            body: body
        )
    }

    func deleteUserExercise(id: String) async throws {
        let _: RemoteExerciseDeleteResponse = try await apiHelper.asyncAuthorizedRequestData(
            route: APIRoute.exercise(id: id),
            httpMethod: .DELETE
        )
    }

    func restoreUserExercise(id: String) async throws -> GymTrackerExerciseDTO {
        try await apiHelper.asyncAuthorizedRequestData(
            route: ExerciseRestoreRoute(exerciseId: id),
            httpMethod: .POST
        )
    }

    func updateCatalogOverlay(
        npId: String,
        aliases: [String],
        isArchived: Bool
    ) async throws -> GymTrackerExerciseDTO {
        let body = RemoteCatalogOverlayUpdateBody(
            aliases: aliases,
            isArchived: isArchived
        )

        return try await apiHelper.asyncAuthorizedRequestData(
            route: APIRoute.exercise(id: npId),
            httpMethod: .PATCH,
            body: body
        )
    }
}

extension RemoteExerciseRepository: RemoteExerciseBootstrapUploading {
    func upsertForBootstrap(_ exercise: Exercise) async throws {
        _ = try await upsertUserExercise(exercise)
    }
}

final class AuthenticatedUserExerciseSource: UserExerciseSource {
    private let repository: RemoteExerciseRepository

    init(repository: RemoteExerciseRepository = RemoteExerciseRepository()) {
        self.repository = repository
    }

    var routeDescription: String {
        "/v1/exercises?source=user"
    }

    func fetchUserExercises() async throws -> [GymTrackerExerciseDTO] {
        let items = try await repository.fetchUserExercises(
            updatedAfter: nil,
            deletedAfter: nil,
            includeDeleted: true
        )
        return items.filter(isExpectedUserRecord(_:))
    }

    private func isExpectedUserRecord(_ dto: GymTrackerExerciseDTO) -> Bool {
        let source = dto.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "user" {
            return true
        }
        if source == "catalog" {
            return false
        }

        // Defensive fallback for older payload variants with inconsistent source fields.
        if UUID(uuidString: dto.id) != nil {
            return true
        }
        return dto.isUserCreated
    }
}

final class AuthenticatedCatalogOverlaySource: CatalogOverlaySource {
    private let repository: RemoteExerciseRepository

    init(repository: RemoteExerciseRepository = RemoteExerciseRepository()) {
        self.repository = repository
    }

    var routeDescription: String {
        "/v1/exercises/catalog-overlays"
    }

    func fetchCatalogOverlays(updatedAfter: Date?) async throws -> [GymTrackerCatalogOverlayDTO] {
        try await repository.fetchCatalogOverlays(updatedAfter: updatedAfter)
    }
}

private struct RemoteExerciseDeleteResponse: Decodable {
    let ok: Bool
    let id: String
    let deletedAt: String?
}
