# GymTracker Notes Import System Architecture

Author: Internal Implementation Plan  
Target: Swift + SwiftUI + SwiftData  
Status: Phased, Non-Destructive Migration

------------------------------------------------------------------------

# OVERVIEW

This document defines the architecture for importing workout sessions from free-form Notes text into GymTracker.

Goals:
- Parse strength + cardio workouts
- Support per-side weight + bar notation
- Support rest times
- Support multiple sessions in one paste
- Show draft preview before database write
- Perform duplicate detection
- Resolve routine + exercise references
- Keep migration non-destructive

Global decisions:
- Cardio is `ExerciseType.run`, `ExerciseType.bike`, or `ExerciseType.swim`.
- `SessionRep.weight` remains TOTAL working weight for workload calculations.
- `Session.importHash` is optional and computed per split session block.
- Import may assign a routine.
- Routine template mutation safety:
  - Existing routines must not be mutated by import.
  - If a routine is newly created during the same import commit, template population is allowed for that newly created routine only.
- Commit behavior is all-or-nothing per draft/session block.
- All matching, duplicate detection, and writes are scoped to `currentUserId` only.
- No global queries and no cross-user matching.
- Parsing/preview is allowed without user_id; commit is blocked until `currentUserId` exists.
- Weightless strength sets persist deterministically as `weight = 0` with a rep note and a default weight unit policy.

Phase map (authoritative for this document):
- Phase 1: Model extensions
- Phase 2: Import domain models
- Phase 3: Parser engine
- Phase 4: Duplicate detection
- Phase 5: Resolution engine
- Phase 6: Draft preview UI
- Phase 7: Database write pipeline
- Phase 8: UI logic differentiation (cardio vs strength)
- Phase 9: Cardio multi-interval support
- Phase 10: Error recovery
- Phase 11: Backup schema compatibility

------------------------------------------------------------------------

# PHASE 1 --- MODEL EXTENSIONS (NON-DESTRUCTIVE)

## 1.1 SessionSet Additions

Add optional properties:
- `durationSeconds: Int? = nil`
- `distance: Double? = nil`
- `paceSeconds: Int? = nil`
- `distanceUnitRaw: String? = nil`
- `restSeconds: Int? = nil`

Distance unit:

```swift
enum DistanceUnit: String, Codable {
    case km
    case mi
}
```

Computed:

```swift
var distanceUnit: DistanceUnit {
    get { DistanceUnit(rawValue: distanceUnitRaw ?? "km") ?? .km }
    set { distanceUnitRaw = newValue.rawValue }
}
```

## 1.2 SessionRep Additions

Add:
- `baseWeight: Double? = nil`
- `perSideWeight: Double? = nil`
- `isPerSide: Bool = false`

Semantics:
- `weight` remains TOTAL weight used for workload.
- `baseWeight` and `perSideWeight` are for traceability/UI and must not alter workload unless user edits `weight`.

Optional UI helper:

```swift
var derivedTotalWeight: Double? {
    guard isPerSide, let base = baseWeight, let side = perSideWeight else { return nil }
    return base + (side * 2)
}
```

## 1.3 Session Additions

Add:
- `importHash: String? = nil`

Used for duplicate detection. Existing sessions may keep `nil`.

## 1.4 Routine Additions

Add:
- `aliases: [String] = []`

Normalization for alias matching:
- lowercase
- trim whitespace
- remove punctuation
- collapse multiple spaces

------------------------------------------------------------------------

# PHASE 2 --- IMPORT DOMAIN MODELS (NO DATABASE WRITES)

Create import-only structures:

```swift
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
```

Weightless/default unit policy:
- Parsing may produce `weight == nil`.
- Writer commit must persist a rep with `weight = 0`.
- `weightUnit` defaults to user preferred unit when missing (fallback `.lb`).
- Rep note must include: `Imported: weight not specified (treated as 0).`

------------------------------------------------------------------------

# PHASE 3 --- PARSER ENGINE

Create `NotesImportParser`.

Public API:

```swift
final class NotesImportParser {
    func parseBatch(from text: String, defaultWeightUnit: WeightUnit) -> NotesImportBatch
    func parseSingleSession(from text: String, defaultWeightUnit: WeightUnit) -> NotesImportDraft
}
```

Responsibilities:
- Split multiple sessions by date lines
- Extract headers
- Parse numbered lines
- Parse strength sets
- Parse per-side + bar
- Parse cardio metrics
- Preserve unknown lines
- Accept `defaultWeightUnit: WeightUnit` from ViewModel input.

Cardio helper:

```swift
extension ExerciseType {
    var isCardio: Bool {
        switch self {
        case .run, .bike, .swim:
            return true
        default:
            return false
        }
    }
}
```

## 3.1 Date Detection

Support formats:
- `December 15, 2025`
- `Nov 15, 2022`

Regex pattern: `MonthName Day, Year`

## 3.2 Strength Parsing Rules

Supported patterns:
- `3x10, 235lbs`
- `2x10, 205lbs, 1x10, 225lbs`
- `1x8, 35kg per side, 20kg bar`
- `3 sets of 10, 85 pounds`

Parsing steps:
1. Extract exercise name before first comma
2. Split remaining segments by comma
3. Detect tokens: `NxR`, `sets of`, weight (`kg/lb`), `per side`, `bar`, rest (`1:30m rest`)

Per-side import rule:
- For `35kg per side, 20kg bar`: store `baseWeight=20`, `perSideWeight=35`, `isPerSide=true`, and TOTAL `weight=90`.

Weight unit fallback rule:
- Keep `ParsedStrengthSet.weightUnit` non-optional.
- If parsed unit is missing, parser sets `weightUnit = defaultWeightUnit`.

## 3.3 Cardio Parsing Rules

Detect cardio by:
- `exercise.exerciseType.isCardio`
- or fallback keywords (run, walk, treadmill, indoor) when exercise resolution is unavailable

Supported patterns:
- `5km, 29min`
- `1km, 5:15min`
- `20min, 2km`

Convert:
- minutes to seconds
- `mm:ss` to seconds

## 3.4 Rest Parsing

Pattern: `1:30m rest` -> `90 seconds`

## 3.5 Time Range Parsing + Timezone Rules

Deterministic rules:
- Parse time ranges in strict formats only:
  - 24-hour: `HH:mm-HH:mm` (two-digit hour + two-digit minute on both sides)
  - 12-hour: `h:mmam-h:mmpm` (AM/PM required on both sides; spaces optional; case-insensitive)
- Reject mixed/ambiguous formats:
  - Missing AM/PM on either side in 12-hour style
  - Mixed 24-hour with AM/PM
- Use device current timezone.
- If `endTime < startTime`, treat as cross-midnight and add +1 day to `endTime`.
- If time parsing fails, leave time values nil and add a draft warning.

------------------------------------------------------------------------

# PHASE 4 --- DUPLICATE DETECTION

Hash normalization (canonical):
- lowercase
- unicode normalize (NFKD optional)
- replace non-alphanumeric chars (except `:`) with spaces
- collapse repeated whitespace to one space
- trim

Generate SHA256 from normalized text.

Scope:
- Split batch into session blocks first.
- Compute one hash per resulting session block.
- Store hash on `Session.importHash` (optional).

Before saving draft:
- query `Session` where `user_id == currentUserId` and `importHash == draft.importHash`
- if exists, prompt: `Seems like this session was already imported. Import anyway?`

User scoping:
- Duplicate checks are per-user only.
- Resolver and writer must not perform global queries.

------------------------------------------------------------------------

# PHASE 5 --- RESOLUTION ENGINE

Before DB write resolve:
- routine
- exercises

User scoping:
- Importer accepts `currentUserId`.
- Routine and exercise matching are filtered by `user_id == currentUserId`.
- No cross-user resolution is allowed.

If routine not found:
- select existing
- create new
- no routine

If exercise not found:
- select existing
- create new
- add alias

Routine mutation constraints:
- Import may assign a routine to a session.
- Import may add routine alias only with user approval.
- Existing routine templates must not be mutated.
- Newly created routine templates (created in the same import commit) may be populated from imported exercise order.
- Import must not change routine current/template status.

------------------------------------------------------------------------

# PHASE 6 --- DRAFT PREVIEW UI

Flow:
- Paste Screen
- Parse
- Draft Preview
- Resolve Routine
- Resolve Exercises
- Confirm Import

Allow swiping between drafts for multi-session paste.

Default weight unit source:
- Import flow accepts `defaultWeightUnit: WeightUnit`.
- Import UI provides this value through a picker, defaulting to `.lb`.
- Parser does not read preferences directly; ViewModel passes `defaultWeightUnit` into parser/writer flow.
- Parser assigns `weightUnit = defaultWeightUnit` when unit is missing.
- Do not depend on global app settings or HealthKit for this value.

Timestamp mapping + resolution rules:
- Parsing/preview may contain missing date/time values.
- Commit is blocked until date/time are explicitly resolved.
- No silent commit-time fallback to `Date()` / “now”.
- Import UI must provide a date/time resolver with:
  - Start DateTime picker
  - End DateTime picker
  - Explicit user confirmation for date and time-range when they were missing from parsed notes
- Resolver coupling behavior:
  - If start changes, end shifts by the same delta (preserve duration).
  - If end changes earlier than start, start snaps to end (duration 0).
- If start/end exist after resolution: map to `Session.timestamp` and `Session.timestampDone`.

------------------------------------------------------------------------

# PHASE 7 --- DATABASE WRITE PIPELINE

After confirmation, per draft:
1. Create `Session`
2. Set `importHash`
3. Attach routine if selected
4. For each `ParsedItem`:
   - Create `SessionEntry`
   - Strength: create `SessionSet` + `SessionRep` records
   - Cardio: create `SessionSet` without reps

Transaction and failure behavior:
- Each draft is one transaction (all-or-nothing per draft).
- If one draft fails, other drafts may still import.
- Failed drafts remain editable with fix suggestions.

Writer transaction semantics (per draft):
- Create objects for the current draft.
- Call `try context.save()`.
- If save fails: call `context.rollback()`, mark draft failed, show error, continue to next draft.
- No retry logic and no background-thread transaction redesign.

Writer requirements:
- Writer requires `currentUserId` and sets `Session.user_id` explicitly.
- Writer uses `NotesImportWriterService` and `ModelContext` directly; no SessionService UI-state APIs.
- If no current user is available, commit is blocked.

------------------------------------------------------------------------

# PHASE 8 --- UI LOGIC DIFFERENTIATION

In `SessionExerciseView`:

```swift
if exercise.exerciseType.isCardio {
    showCardioSetView()
} else {
    showStrengthSetView()
}
```

Acceptance criteria:
- Cardio `SessionSet` may have `sessionReps.count == 0`.
- UI must not crash when reps are empty.
- Any reps-based calculation must guard for cardio/empty reps.

------------------------------------------------------------------------

# PHASE 9 --- CARDIO MULTI-INTERVAL SUPPORT

Consecutive rules:
- Same-exercise cardio lines may append sets to same `SessionEntry` only when consecutive with no different exercise in between.
- If same exercise appears later after different exercises, create a new `SessionEntry`.

------------------------------------------------------------------------

# PHASE 10 --- ERROR RECOVERY

Parser never throws.

Collect and display:
- warnings
- unknown lines

Never discard recoverable data.

------------------------------------------------------------------------

# PHASE 11 --- BACKUP SCHEMA COMPATIBILITY

Backup compatibility (Path A: defer backup update):
- New fields (`Session.importHash`, cardio set fields, per-side trace fields, routine aliases) are ignored by Backup v1 unless backup schema is updated.
- If backup/export is not updated immediately, these fields may be dropped on export/import.
- Import feature still works without backup v2.
- Future work: add Backup schema v2 with DTO/version/read/write updates for the new optional fields.

------------------------------------------------------------------------

# ENTRY POINT INTEGRATION

Import launch point:
- Sessions list screen toolbar includes `Import from Notes`.

Required context:
- `ModelContext`
- `currentUserId`

Post-commit visibility:
- Imported sessions appear in the Sessions list for the active user.

------------------------------------------------------------------------

# FUTURE EXTENSIONS

Possible future support:
- RPE
- Tempo
- Interval timers
- Plate math UI
- Auto workout detection from Apple Health

------------------------------------------------------------------------

# MIGRATION SAFETY

All new fields are optional. No required fields changed. Existing sessions must load even when new fields are `nil`.

------------------------------------------------------------------------

# END OF DOCUMENT
