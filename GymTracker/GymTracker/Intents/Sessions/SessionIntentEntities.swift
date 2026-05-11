import AppIntents
import Foundation

struct SessionRoutineEntity: AppEntity {
    static let defaultQuery = SessionRoutineEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Routine")

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "list.bullet.rectangle")
        )
    }
}

struct SessionRoutineEntityQuery: EntityStringQuery {
    func entities(for identifiers: [SessionRoutineEntity.ID]) async throws -> [SessionRoutineEntity] {
        try await MainActor.run {
            try SessionIntentStore.routineEntities(identifiers: identifiers)
        }
    }

    func entities(matching string: String) async throws -> [SessionRoutineEntity] {
        try await MainActor.run {
            try SessionIntentStore.routineEntities(matching: string)
        }
    }

    func suggestedEntities() async throws -> [SessionRoutineEntity] {
        try await MainActor.run {
            try SessionIntentStore.suggestedRoutineEntities()
        }
    }
}

struct SessionProgrammeEntity: AppEntity {
    static let defaultQuery = SessionProgrammeEntityQuery()
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Programme")

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "figure.walk.motion")
        )
    }
}

struct SessionProgrammeEntityQuery: EntityStringQuery {
    func entities(for identifiers: [SessionProgrammeEntity.ID]) async throws -> [SessionProgrammeEntity] {
        try await MainActor.run {
            try SessionIntentStore.programmeEntities(identifiers: identifiers)
        }
    }

    func entities(matching string: String) async throws -> [SessionProgrammeEntity] {
        try await MainActor.run {
            try SessionIntentStore.programmeEntities(matching: string)
        }
    }

    func suggestedEntities() async throws -> [SessionProgrammeEntity] {
        try await MainActor.run {
            try SessionIntentStore.suggestedProgrammeEntities()
        }
    }
}
