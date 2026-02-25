# Notes Import Refinement Plan (Relaxed + Minimal Schema Change)

## Summary
Refine notes import to be more forgiving, preserve user intent, and improve correction UX while keeping schema changes minimal.

Explicit constraints:
- Do not change service function headers.
- Do not change or remove `override func loadFeature`.
- Refresh behavior must be done inside existing methods or via lightweight state invalidation/notification.
- Persistent fractional-rep field was removed from plan.

## Interfaces and Data Shape
- Keep persistent model changes minimal.
- Add import-domain support only:
  - `ParsedStrengthSet.repSegments: [ParsedRepSegment]`
  - `ParsedRepSegment { reps: Int, weight: Double?, weightUnit: WeightUnit, sourceRawReps: String? }`
- No new persistent fractional reps field (no `SessionRep.rawCount`).

## 1) Parser Relaxation + Coverage
- Time range support:
  - Accept `5:19-6:15` (24h short-hour style) and existing AM/PM forms.
- Drop sets support (explicit):
  - Input: `2x6 25kg +3 22.5kg`
  - Parsed output: **2 sets**, each set has **2 rep segments** in order:
    - `6 reps @ 25kg`
    - `3 reps @ 22.5kg`
  - Representation: first segment is main weight; `+` segments are additional segments for the same set.
- Fractional reps behavior (import-domain only):
  - Parser may recognize `5.5` and `5 1/2`.
  - Persisted reps remain `Int`.
  - Consistent policy: **round to nearest Int**.
  - Add import note for auditability, e.g. `Imported as 6 reps (from 5.5)`.
- Bodyweight sequence support:
  - Parse lines like pull-ups `10, 6` as `1x10`, `1x6` where exercise context indicates rep-only strength notation.
- Bracket notes:
  - Preserve bracketed unknown tokens as notes attached to nearest parsed item.

## 2) Unknown Lines: Deterministic Color Rules
- Orange: context lines outside exercise span (before first parsed exercise line, after last parsed exercise line).
- Red: exercise-like line inside exercise span that fails parsing.
  - Exercise-like means tokens such as `x`, `kg/lb`, comma-separated rep counts, or numeric set patterns.
- Neutral/info: everything else.
- Locker number lines default to **orange** notes, not red errors.

## 3) Paste UX
- Keep two buttons:
  - `Paste Add` (primary, safer default, appends)
  - `Paste Replace` (secondary/destructive, replaces editor text)

## 4) Writer + Persistence Mapping
- Drop sets mapping must preserve set count and order:
  - One `SessionSet` per top-level set.
  - Each set’s `repSegments` become multiple `SessionRep` rows under that `SessionSet`, in segment order.
- Fractional reps persistence:
  - Persist integer reps only (rounded policy above).
  - Append original fractional value to notes for traceability.
- Unknown/context lines:
  - Persist as notes/warnings without noisy parser-error wording for benign context.

## 5) Post-Import Visibility and Linking Reliability
- Keep this fix without service/header refactors:
  - Do **not** change service function headers.
  - Do **not** remove/alter `override func loadFeature`.
- Fix approach:
  - Ensure routine -> exercise detail path uses the same effective fetch predicate/data source assumptions as other entry paths.
  - Trigger view invalidation/re-fetch on import completion using lightweight state invalidation (e.g., `didImport` published flag in view model or lightweight notification).
  - No signature changes required.

## 6) Documentation Alignment
- Update notes-import docs to match implementation behavior above.
- Add explicit examples for:
  - `2x6 25kg +3 22.5kg`
  - `5:19-6:15`
  - rep-only pull-up style
  - locker/context note handling

## Test Scenarios
- Parser:
  - `2x6 25kg +3 22.5kg` produces exactly 2 sets × 2 segments each.
  - `5.5` and `5 1/2` recognized and rounded consistently.
  - `5:19-6:15` parses.
  - rep-only pull-up line parses.
  - orange/red/neutral classification follows deterministic rules.
- Writer:
  - Drop segment order preserved in reps under each set.
  - Fractional rounding note appended.
- UI:
  - `Paste Add` appends and is primary.
  - `Paste Replace` replaces and is secondary/destructive.
  - Post-import detail pages show consistent session history across routine, session, and exercise navigation paths.

## Assumptions and Defaults
- Fractional reps are not persisted as decimal fields.
- Fractionals are represented as integer reps plus notes, consistent with common logging app behavior and community-reported workflows ([Reddit][1]).
- Minimal schema change remains a hard requirement.

[1]: https://www.reddit.com/r/StrongApp/

## Execution Guardrails (Mandatory)

- Work in controlled phases only; do not batch all changes at once.
- Project must compile after each phase before moving to the next phase.
- Do not change any service function headers.
- Do not modify or remove `override func loadFeature`.
- Do not silently alter service behavior; if a service is touched, keep logic local and explicitly scoped to this feature.
- Do not refactor unrelated files.
- Prefer small isolated diffs over broad rewrites.
- Keep persistence schema stable unless explicitly approved in this plan.

## Controlled Phases

### Phase 1 — Drop Set Parsing

Scope:
- Implement parser support for `ParsedStrengthSet.repSegments: [ParsedRepSegment]`.
- Ensure input `2x6 25kg +3 22.5kg` parses as **2 sets**, each with **2 rep segments** in order:
  - `6 reps @ 25kg`
  - `3 reps @ 22.5kg`
- Update writer mapping:
  - One top-level parsed set => one `SessionSet`
  - Drop segments => multiple `SessionRep` rows under that set
  - Preserve order
- No persistence schema changes.

Risk guard:
- Do not duplicate segments across sets.
- Do not treat `+3 22.5kg` as a standalone top-level set.
- Preserve segment ordering when writing multiple `SessionRep` rows for a single `SessionSet`.

Compile gate:
- Build project successfully before starting Phase 2.

### Phase 2 — Fractional Rep Handling (Import-only)

Scope:
- No new model fields.
- Parser may detect fractional reps (`5.5`, `5 1/2`).
- Persist integer reps only using one policy: **round to nearest Int**.
- Append note for traceability, e.g. `Imported as 6 reps (from 5.5)`.
- Keep existing volume calculations unchanged.

Compile gate:
- Build project successfully before starting Phase 3.

### Phase 3 — Line Classification UI

Scope:
- Implement deterministic line classifications for preview only:
  - Orange = outside exercise span (before first parsed exercise, after last parsed exercise)
  - Red = exercise-like line inside exercise span that fails parsing
  - Neutral/info = everything else
- Locker-number lines default to orange.
- Classification must not change parse/write logic.

Compile gate:
- Build project successfully before starting Phase 4.

### Phase 4 — Paste UX

Scope:
- Add two paste actions:
  - `Paste Add` (primary, appends text)
  - `Paste Replace` (secondary/destructive, replaces text)
- Keep parsing flow unchanged.

Compile gate:
- Build project successfully before starting Phase 5.

### Phase 5 — Post-import Visibility Bug

Scope:
- Do not modify service signatures.
- Fix routine -> exercise detail history path so query behavior matches other entry paths.
- Ensure fetch predicate filters by `exercise.id` and `userId` only, and does not depend on routine context.
- Trigger lightweight invalidation after successful import (observable state or notification), without global refresh hacks.
- No unrelated service refactor.

Compile gate:
- Build project successfully and run targeted manual verification for all entry paths.
