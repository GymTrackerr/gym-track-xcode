import AppIntents
import Foundation

enum SessionStartKind: String, AppEnum, CaseIterable {
    case blank
    case routine
    case programme

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Session Type")
    static var caseDisplayRepresentations: [SessionStartKind: DisplayRepresentation] = [
        .blank: DisplayRepresentation(
            title: "Blank",
            subtitle: "Start without a routine",
            image: .init(systemName: "plus.circle")
        ),
        .routine: DisplayRepresentation(
            title: "Routine",
            subtitle: "Use a saved routine",
            image: .init(systemName: "list.bullet.rectangle")
        ),
        .programme: DisplayRepresentation(
            title: "Programme",
            subtitle: "Start the next workout",
            image: .init(systemName: "figure.walk.motion")
        )
    ]
}
