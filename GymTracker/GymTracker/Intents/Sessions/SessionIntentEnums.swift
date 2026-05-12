import AppIntents
import Foundation

enum SessionStartKind: String, AppEnum, CaseIterable {
    case blank
    case routine
    case programme

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "sessions.intent.startKind.type",
        defaultValue: "Session Type",
        table: "Sessions",
        comment: "Type name for the session type App Intent enum."
    ))
    static var caseDisplayRepresentations: [SessionStartKind: DisplayRepresentation] = [
        .blank: DisplayRepresentation(
            title: LocalizedStringResource(
                "sessions.intent.startKind.blank.title",
                defaultValue: "Blank",
                table: "Sessions",
                comment: "Blank session type title."
            ),
            subtitle: LocalizedStringResource(
                "sessions.intent.startKind.blank.subtitle",
                defaultValue: "Start without a routine",
                table: "Sessions",
                comment: "Blank session type subtitle."
            ),
            image: .init(systemName: "plus.circle")
        ),
        .routine: DisplayRepresentation(
            title: LocalizedStringResource(
                "sessions.intent.startKind.routine.title",
                defaultValue: "Routine",
                table: "Sessions",
                comment: "Routine session type title."
            ),
            subtitle: LocalizedStringResource(
                "sessions.intent.startKind.routine.subtitle",
                defaultValue: "Use a saved routine",
                table: "Sessions",
                comment: "Routine session type subtitle."
            ),
            image: .init(systemName: "list.bullet.rectangle")
        ),
        .programme: DisplayRepresentation(
            title: LocalizedStringResource(
                "sessions.intent.startKind.programme.title",
                defaultValue: "Programme",
                table: "Sessions",
                comment: "Programme session type title."
            ),
            subtitle: LocalizedStringResource(
                "sessions.intent.startKind.programme.subtitle",
                defaultValue: "Start the next workout",
                table: "Sessions",
                comment: "Programme session type subtitle."
            ),
            image: .init(systemName: "figure.walk.motion")
        )
    ]
}
