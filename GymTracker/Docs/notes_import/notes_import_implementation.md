# GymTracker Notes Import System --- Implementation v3 (Build-Grade)

Author: Internal Engineering Spec  
Target: Swift + SwiftUI + SwiftData  
Scope: Strength + Cardio + Batch Import + Resolution + Duplicate Detection  
Non-Destructive: YES

-----------
IMPORTANT
-----------

This document is used with the architecture document.
If any contradiction appears, architecture constraints win.

Global mandatory rules:
- All matching, duplicate detection, and writes are scoped to `currentUserId`.
- No global queries and no cross-user matching.
- Parsing/preview is allowed without user_id; commit is blocked until `currentUserId` exists.
- Cardio is `ExerciseType.run`, `ExerciseType.bike`, or `ExerciseType.swim` via `.isCardio`.
- `SessionRep.weight` is TOTAL working weight used for workload.

Phase map:
- Phase 1: Model extensions
- Phase 2: Import domain layer
- Phase 3: Parser engine
- Phase 4: Duplicate detection
- Phase 5: Resolution engine
- Phase 6: Draft preview viewmodel
- Phase 7: Database write pipeline
- Phase 8: UI logic differentiation
- Phase 9: Multi-interval cardio
- Phase 10: Error recovery
- Phase 11: Backup schema compatibility

------------------------------------------------------------------------

PHASE 1 --- MODEL EXTENSIONS (SAFE + NON-DESTRUCTIVE)

1.1 Extend SessionSet

Add optional properties:

```swift
var durationSeconds: Int? = nil
var distance: Double? = nil
var paceSeconds: Int? = nil
var distanceUnitRaw: String? = nil
var restSeconds: Int? = nil
```

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

No existing required fields changed.

------------------------------------------------------------------------

1.2 Extend SessionRep

Keep existing required fields (`weight`, `count`) and add:

```swift
var baseWeight: Double? = nil
var perSideWeight: Double? = nil
var isPerSide: Bool = false
```

Semantics:
- `weight` remains TOTAL working weight and is the source for workload calculations.
- `baseWeight` + `perSideWeight` are metadata for traceability and UI.
- Do not change workload math to rely on a computed total.

Optional UI helper:

```swift
var derivedTotalWeight: Double? {
    guard isPerSide, let base = baseWeight, let side = perSideWeight else { return nil }
    return base + (side * 2)
}
```

Import rule example:
- Input `1x8, 35kg per side, 20kg bar`
- Persist `baseWeight=20`, `perSideWeight=35`, `isPerSide=true`, `weight=90`.

------------------------------------------------------------------------

1.3 Extend Session

Add:

```swift
var importHash: String? = nil
```

`importHash` remains optional so older sessions continue loading.

------------------------------------------------------------------------

1.4 Extend Routine

Add:

```swift
var aliases: [String] = []
```

Routine alias matching normalization:
- lowercase
- trim
- punctuation removed
- collapse multiple spaces

------------------------------------------------------------------------

PHASE 2 --- IMPORT DOMAIN LAYER (NO DATABASE WRITES)

Create file: `NotesImportModels.swift`

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
- Parsing may output `weight == nil` for strength sets.
- On commit, writer persists `SessionRep.weight = 0`.
- `weightUnit` defaults to user preferred unit when missing (fallback `.lb`).
- Writer sets `SessionRep.notes = "Imported: weight not specified (treated as 0)."` for that rep.

------------------------------------------------------------------------

PHASE 3 --- PARSER ENGINE

Create: `NotesImportParser.swift`

Public API:

```swift
final class NotesImportParser {
    func parseBatch(from text: String, defaultWeightUnit: WeightUnit) -> NotesImportBatch
    func parseSingleSession(from text: String, defaultWeightUnit: WeightUnit) -> NotesImportDraft
}
```

3.1 Batch Split Strategy
- Detect date lines via regex
- Split text into session blocks
- If no date found -> single draft

3.2 Date Detection Regex
- Support examples: `December 15, 2025`, `Nov 15, 2022`
- Use month name list

3.3 Strength Parsing Strategy

Algorithm:
1. Extract exercise name (before first comma)
2. Split remaining segments by comma
3. Detect tokens:
- `NxR` (for example `3x10`)
- `sets of`
- weight token (`kg/lb`)
- `per side`
- `bar`
- rest token (`1:30m rest`)

3.4 Per-Side + Bar Parsing

Example: `1x8, 35kg per side, 20kg bar`

Persist:
- `baseWeight = 20`
- `perSideWeight = 35`
- `isPerSide = true`
- `weight = 90` (TOTAL)

If only `90kg`:
- `weight = 90`
- `isPerSide = false`

Weight unit fallback rule:
- Keep `ParsedStrengthSet.weightUnit` non-optional.
- If parsed unit is missing, parser sets `weightUnit = defaultWeightUnit`.

3.5 Cardio Parsing Strategy

Cardio definition:
- `ExerciseType.run`, `.bike`, `.swim`
- Branch with `exercise.exerciseType.isCardio`

```swift
extension ExerciseType {
    var isCardio: Bool {
        switch self {
        case .run, .bike, .swim: return true
        default: return false
        }
    }
}
```

When exercise is unresolved, fallback keyword detection is allowed.

Patterns:
- `5km`
- `29min`
- `5:15min`
- `20min, 2km`

Conversions:

```swift
func parseDuration(_ string: String) -> Int?
func parseDistance(_ string: String) -> (Double, DistanceUnit)?
func parsePace(_ string: String) -> Int?
```

3.6 Rest Parsing
- Pattern: `1:30m rest`
- Convert to seconds

3.7 Time Range Parsing + Timezone Rules
- Parse time ranges only in `HH:mm-HH:mm` 24-hour format.
- Use device current timezone.
- If `endTime < startTime`, treat as cross-midnight and add +1 day to `endTime`.
- If time parsing fails, keep time values nil and append a draft warning.

------------------------------------------------------------------------

PHASE 4 --- DUPLICATE DETECTION

Utility:

```swift
func generateImportHash(for text: String) -> String
```

Canonical normalization:
- lowercase
- unicode normalize (NFKD optional)
- replace non-alphanumeric chars (except `:`) with spaces
- collapse repeated whitespace to one space
- trim
- SHA256

Hash scope:
- Split batch first.
- Compute hash per split session block.
- Store into `Session.importHash` (optional).

Before commit:
- Query `Session` where `user_id == userId` and `importHash == draft.importHash`
- If exists, prompt user before writing

Compatibility:
- Older sessions with `nil importHash` remain valid

------------------------------------------------------------------------

PHASE 5 --- RESOLUTION ENGINE

Create: `NotesImportResolver.swift`

Responsibilities:
- Resolve routine by normalized match
- Resolve exercise by normalized match
- Handle alias addition
- Track unresolved items

Public API:

```swift
struct ResolutionResult {
    var resolvedRoutine: Routine?
    var resolvedExercises: [String: Exercise]
    var unresolvedExercises: [String]
}
```

Resolver API requirement:
- `NotesImportResolver.resolve(..., userId: UUID)` filters routine/exercise fetches by `user_id == userId`.

Routine mutation rules:
- Assigning routine to session is allowed.
- Import must not mutate routine exercise list/order/template state.
- Only allowed routine mutation: add alias when user approves "remember alias".

------------------------------------------------------------------------

PHASE 6 --- DRAFT PREVIEW VIEWMODEL

Create: `NotesImportViewModel`

Properties:

```swift
@Published var batch: NotesImportBatch
@Published var currentDraftIndex: Int
@Published var resolutionState: ResolutionState
```

Functions:
- `parseInput(text:)`
- `moveToNextDraft()`
- `resolveRoutine()`
- `resolveExercise()`
- `confirmImport()`

Default weight unit source:
- Import flow accepts `defaultWeightUnit: WeightUnit`.
- Import UI supplies this value from a picker with `.lb` default.
- Parser does not read preferences directly; ViewModel passes `defaultWeightUnit` into parser/writer flow.
- Parser assigns `weightUnit = defaultWeightUnit` when unit is missing.
- Writer uses `defaultWeightUnit` when parsed weight or parsed weight unit is missing.
- Do not use global app settings or HealthKit as the source.

Timestamp prep rules in preview:
- If `parsedDate == nil`, draft cannot commit until user selects a date.
- If date exists and no time range, prefill start at 12:00 local time and show warning.
- If end time is missing and `timestampDone` is non-optional, preview warning must state: `Missing end time; estimated end time will be used.`

------------------------------------------------------------------------

PHASE 7 --- DATABASE WRITE PIPELINE

Replace UI-bound session creation calls with dedicated writer:

Create: `NotesImportWriterService`

Responsibilities:
- Accept fully resolved `NotesImportDraft`
- Require `userId: UUID` and set `Session.user_id` explicitly
- Use `ModelContext` directly
- Create `Session`, `SessionEntry`, `SessionSet`, and strength `SessionRep`
- Keep import flow independent from `SessionService` UI state

Acceptance criteria:
- No SessionService API changes required for import
- Writer service is used only by import flow

Write rules per draft:
1. Validate required date
2. Create `Session`
3. Set `Session.importHash`
4. Attach resolved routine if any
5. Map timestamps:
- if `parsedDate == nil`: block commit
- if date + start/end exist: set `timestamp` and `timestampDone`
- if date exists but time missing: set `timestamp` to 12:00 local, set `timestampDone = timestamp + 60 minutes`, add warning `Missing end time; estimated end time used.`
6. For each parsed item:
- create `SessionEntry`
- strength: create sets + reps
- cardio: create sets only (no reps)

Transaction behavior:
- One transaction per draft (all-or-nothing)
- If one draft fails, other drafts can still import
- Failed draft stays editable with actionable fix suggestions

Writer transaction pseudocode (per draft):
```text
create objects
try context.save()
if save fails:
    context.rollback()
    mark draft as failed
    show error
    continue to next draft
```
- Do not add retry logic.
- Do not introduce background-thread writer logic.

Writer API requirement:
- `NotesImportWriterService.commit(draft:..., userId: UUID, context: ModelContext)`
- If current user is missing, block commit with user-facing message.
- Do not route import writes through SessionService UI-state APIs.

------------------------------------------------------------------------

PHASE 8 --- UI LOGIC DIFFERENTIATION

In `SessionExerciseView`:

```swift
if exercise.exerciseType.isCardio {
    showCardioSetView()
} else {
    showStrengthSetView()
}
```

Acceptance criteria:
- Cardio `SessionSet` may have `sessionReps.count == 0`
- UI must not crash when reps are empty
- Any reps-based calculation must guard for cardio/empty reps

------------------------------------------------------------------------

PHASE 9 --- MULTI-INTERVAL CARDIO

Rule:
- A cardio line becomes a new `SessionSet` under current `SessionEntry` only if same normalized exercise name and no different exercise line appeared in between.
- If the same exercise appears later after different exercises, create a new `SessionEntry`.

------------------------------------------------------------------------

PHASE 10 --- ERROR RECOVERY

Parser never throws. Collect and surface:
- warnings
- unknownLines

Do not discard recoverable data.

------------------------------------------------------------------------

PHASE 11 --- BACKUP SCHEMA COMPATIBILITY

Path A (defer backup update):
- New fields (`importHash`, cardio set fields, per-side trace fields, routine aliases) are ignored by Backup v1 unless backup schema is updated.
- If backup/export is not updated immediately, these fields may be dropped on export/import.
- Notes import can ship before backup schema v2.
- Future phase requirement: Backup schema v2 with payload version bump and DTO/read/write updates for new optional fields.

------------------------------------------------------------------------

ENTRY POINT INTEGRATION

Launch point:
- Sessions list screen toolbar action: `Import from Notes`.

Required dependencies:
- `ModelContext`
- `currentUserId`

Post-commit behavior:
- Imported sessions appear in Sessions list for the active user scope.

------------------------------------------------------------------------

DONE CRITERIA CHECKLIST

PHASE 1 DONE:
- App builds
- No migration crash
- Old sessions load correctly with optional new fields

PHASE 3 DONE:
- Example notes parse correctly
- Per-side + bar data parsed with total `weight` persisted
- Cardio detection works via `.isCardio`

PHASE 7 DONE:
- Sessions write through `NotesImportWriterService`
- Duplicate detection works with per-block hashes
- Cardio sets persist with zero reps without UI/runtime errors

------------------------------------------------------------------------

END OF DOCUMENT
