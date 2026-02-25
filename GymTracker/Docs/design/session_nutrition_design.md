You are working in my Xcode project. BEFORE writing any code, you MUST open and read these files and quote the exact function/property names you will reuse:

- SessionsView.swift (or SessionListView.swift)
- SessionService.swift (and any “volume” related helpers)
- SessionExerciseView.swift (if it already computes volume)
- Any existing “Volume” / “Stats” / “Analytics” helpers

Goal: Improve Sessions UI (filter Week/Month/Year/All + summary header + row metadata) WITHOUT duplicating volume logic.

Hard constraints:
- Reuse existing total-volume / session-volume calculation logic. Do NOT re-implement it.
- Do NOT touch model files (SwiftData models, entities, schemas). Do NOT change persistence.
- Do NOT add new stored fields. Computed only.
- Keep changes confined to Sessions view + its view model + small helper extensions ONLY if necessary.
- Keep output short: max 15 bullet points + only the code diff for changed files. No essays.

Process:
1) READ & REPORT: After reading, list where volume is currently computed (file + symbol names). If there is no single reusable function, propose ONE small helper method in SessionService (not models) and justify it in 2 sentences.
2) PLAN: 5–8 bullets for the UI changes.
3) IMPLEMENT: Make the minimal diff. Ensure filter is data-layer-friendly (no O(n) recompute every redraw). Cache per-period summary if needed.
4) VERIFY: Provide a short manual test checklist (5 items max).

Also: Xcode has crashed twice from overly large edits. Keep the diff minimal and avoid refactors/renames.


---
Implement a UI polish pass focused on **Sessions** (primary) and **Nutrition** (secondary). Keep the existing red gradient header/background style. **Do not remove the gradient** and **do not add glass/blur/material effects**. Match the typography hierarchy and spacing style used across the non-dashboard pages (e.g., Exercises/Nutrition list feel), not Home/Program.

### Sessions page goals

1. Add clear visual hierarchy without adding clutter:

* Add a small summary header above the list that updates with the active time range:

  * Title: “This Week / This Month / This Year / All”
  * Metrics (2–4 lines max): Sessions count, Total volume, Avg session volume (and optionally Avg duration if available).
  * Keep it minimal: no charts, no icons beyond existing UI.

2. Add a minimal time-range control at the top (segmented control):

* Options: Week, Month, Year, All
* Default: Month
* Persist selection (AppStorage or equivalent)
* The list query should respect the filter (prefer fetch/filter at data layer; avoid expensive in-memory filtering if the dataset is large).

3. Improve each session row content while keeping it minimal:

* Current row shows date/time + exercise count + routine.
* Update row to show:

  * Primary: Date + time
  * Secondary: Routine name (if present)
  * Tertiary metadata line: “X exercises · Y volume · Z min” (duration optional if available)
* Volume should be computed consistently with existing “Session Volume” logic (same unit handling).
* Keep chevron.
* No extra badges, no extra icons.

4. Sorting + grouping (minimal):

* Keep chronological order newest first.
* Add optional “group by day” section headers (e.g., Feb 22, Feb 21) ONLY if it improves readability; otherwise keep flat list.
* Ensure empty state looks clean (copy like “No sessions in this period” + one CTA button).

5. Styling constraints:

* Reuse existing list card style from other pages (solid/transparent backgrounds as currently used), no glass.
* Increase spacing and typographic contrast rather than borders.
* Ensure accessibility: dynamic type doesn’t break the row layout.

### Nutrition page (small follow-up, keep scope contained)

* Do not redesign the whole screen.
* Make list sections (Breakfast/Lunch/Dinner) match the Sessions list hierarchy:

  * Section headers: slightly stronger weight / spacing.
  * Row content: clear primary vs secondary text.
* Keep existing macro summary card and top kcal number, but ensure spacing aligns with Sessions improvements.
* No glass/blur/material.

### Deliverables

* Provide a concise checklist to verify in-app:

  * Sessions filter switches update summary + list correctly
  * Volume numbers match existing volume calculations
  * Performance is smooth with many sessions
  * Dynamic type sanity check
* Keep the change set limited to Sessions/Nutrition views + their view models/helpers as needed.


---
Do not propose new architecture. No new services. No new files unless absolutely required.
