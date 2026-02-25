import Foundation

struct NotesImportBatch {
    var drafts: [NotesImportDraft]
}

struct NotesImportDraft {
    var originalText: String
    var parsedDate: Date?
    var startTime: Date?
    var endTime: Date?
    var routineNameRaw: String?
    var items: [ParsedItem]
    var unknownLines: [String]
    var warnings: [String]
    var importHash: String
}

enum ParsedItem {
    case strength(ParsedStrength)
    case cardio(ParsedCardio)
}

struct ParsedStrength {
    var exerciseNameRaw: String
    var sets: [ParsedStrengthSet]
    var notes: String?
}

struct ParsedStrengthSet {
    var reps: Int
    var weight: Double?
    var weightUnit: WeightUnit
    var perSideWeight: Double?
    var baseWeight: Double?
    var isPerSide: Bool
    var restSeconds: Int?
    var repSegments: [ParsedRepSegment] = []
}

struct ParsedRepSegment {
    var reps: Int
    var weight: Double?
    var weightUnit: WeightUnit
    var sourceRawReps: String?
}

struct ParsedCardio {
    var exerciseNameRaw: String
    var sets: [ParsedCardioSet]
    var notes: String?
}

struct ParsedCardioSet {
    var durationSeconds: Int?
    var distance: Double?
    var distanceUnit: DistanceUnit
    var paceSeconds: Int?
}
