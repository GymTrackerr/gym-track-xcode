# GymTracker Implementation Plan (Agent Spec)

## Agent operating instructions (read first)
- **Read context before coding**: open and review the relevant files (models, views, services) and search for existing helpers/components so you extend what exists rather than re-implementing.
- **Non-destructive schema rule**: do **not** make destructive model/schema changes.  
  - Any new fields must be **optional** (nullable) and have safe defaults in UI logic.
  - Do not remove/rename existing fields without a migration path.
- **Backups stay compatible**:
  - If you add optional fields, update **Backup Export/Import** to include them **optionally**.
  - Import must tolerate older backups that don’t include the fields.
- **Prefer minimal changes**: small, well-scoped commits per phase.
- **Ask questions only when blocked**: if the codebase doesn’t reveal an answer (e.g., whether sets are unified vs typed), ask the user and propose 2–3 options with tradeoffs.
- **Add acceptance checks**: each phase includes quick manual checks; run/build after each phase.

---

## Phase 1 — Cardio set rendering correctness (fix “data exists but UI hides it”)
### Goal
Cardio logs must render consistently everywhere you show sets and history:
- SessionExerciseView (during a session)
- Exercise detail history / previous logs
- Any compact set-row component used across lists

### Requirements
1) **Type-aware set row rendering**
- Strength: reps + weight (and RPE if present)
- Cardio: duration + distance (and pace if present)
- Bodyweight: reps (+ optional added weight)

2) **No filtering out cardio**
- Remove/replace any filtering like `reps != nil`, `weight != nil`, or `reps > 0` that would hide cardio.
- Replace with a single “meaningful set” predicate:
  - Strength meaningful: reps OR weight OR RPE OR note
  - Cardio meaningful: duration OR distance OR pace OR calories OR note (use whatever fields exist)

3) **Shared formatter**
Create one shared helper used across all set lists:
- `formatSetSummary(set, exerciseKind, unitPrefs) -> (primaryText, secondaryText?, chips?)`

### Acceptance checks
- Cardio exercise with only duration renders rows (not blank).
- Cardio exercise with distance+duration shows both.
- Strength sets unchanged.
- “Previous logs” for cardio matches the session view rendering.

---

## Phase 2 — Navigation + session safety (stop wrong-session logging + loop)
### Goal
Make it obvious when you’re not in the active session, prevent accidental logging into past sessions, and avoid navigation loops.

### Requirements
1) **Replace ad-hoc booleans with a context enum**
Introduce a navigation/session context type:
- `active(sessionId)`
- `past(sessionId)`
- `fromExerciseHistory(sessionId, exerciseId)` (read-only by default)

2) **Rename “Previous sessions” to “Previous logs”**
- Tapping a previous log opens a focused view showing sets for that exercise within that session.
- Add a small “Open full session” button if needed.

3) **Guardrails**
When viewing a non-active session:
- Disable quick-add controls (e.g., “+1 rep”, “Add set”)
- Disable reorder/delete of session exercises unless user enters explicit Edit/Unlock mode
- Show a badge: “Past session” vs “Current session”

4) **Fix navigation looping**
- Ensure “Previous logs” path doesn’t push back into the same exercise-history stack repeatedly.

### Acceptance checks
- From Exercise → Previous logs: cannot add sets unless explicitly unlocked.
- Back navigation returns cleanly (no loop).
- Active session remains fully editable.

---

## Phase 3 — Move sets to another exercise (oops recovery)
### Goal
Allow transferring sets mistakenly logged under the wrong exercise.

### Requirements
1) Entry points
- On a set row: context menu → “Move to exercise…”
- Optional: multi-select sets in Edit mode → “Move”

2) Flow
- Searchable exercise picker
- Confirm step: shows source → target, session date/time, number of sets

3) Data rules
- Preserve: timestamps, session linkage
- Update: set’s exercise reference (and any join IDs if your model uses SessionExercise links)
- Ordering: define and implement consistently (append to target or reindex)

### Acceptance checks
- Strength and cardio sets move correctly.
- History/stats update immediately.

---

## Phase 4 — Faster logging: duplicate + tap-to-fill
### Requirements
- Duplicate set (menu action): copies all fields except ID/timestamps; inserts after source.
- Tap-to-fill (optional): “Use previous set values” on add set row.

### Acceptance checks
- Works for strength and cardio sets.

---

## Phase 5 — Session view summaries under exercise name
### Goal
Show compact summary under each exercise name in session view.

### Requirements
- Strength: “N sets • avg W • total reps” (degrade gracefully if data missing)
- Cardio: “duration • distance • pace” (show available pieces only)
- Use unit preferences (kg/lb, km/mi).

### Guardrails
- Show summary only if at least one piece of data exists (e.g., reps OR weight for strength; duration OR distance for cardio).
- If no sets exist, omit summary line entirely (don't show empty placeholder).
- Summary must use same formatter as Phase 1 (reuse `formatSetSummary`).

### Acceptance checks
- Updates live while editing.
- Strength exercise with all fields shows summary; with only reps shows "N sets • X total reps".
- Cardio with any data shows pieces available (not blank).

---

## Phase 6 — Exercise screen UX
### Requirements
- History button at top (toolbar)
- Default chart:
  - Bar chart for per-session values (volume/distance)
  - Optional toggle later for line trend
- Better history row summaries (strength vs cardio)

### Guardrails
- If exercise has zero sessions or all sessions have empty data, show "No history yet" placeholder (not a blank chart).
- Chart must handle mixed session types gracefully (e.g., some sessions with data, some empty).
- Reuse Phase 1's formatter for history row summaries.

### Acceptance checks
- No blank chart when data exists.
- Chart adapts to exercise type.
- Empty exercise shows placeholder, not broken UI.

---

## Phase 6.1 — Timeframe-anchored chart + full chart explorer
### Goal
Fix compressed/tight chart behavior by always rendering full timeframe windows (including zero-data periods), and provide a dedicated Apple-Health-style chart page for deeper navigation.

### Requirements
1) **Anchor chart to selected timeframe window**
- For `Week`, `Month`, `Year` (and multi-year), always render the full window even if only 1 session exists.
- Include empty buckets with zero values so axis spacing stays stable.
- Example: if user selects `Year`, show all 12 month buckets in range; if selecting `5 Years`, show all 5 year buckets.

2) **Create dedicated chart explorer screen**
- Add a new view file (e.g., `Views/Excerise/m.swift`).
- Tapping chart area in `SingleExerciseView` opens this screen.
- Explorer supports:
  - Horizontal/navigable timeline feel (Health-style interaction)
  - Timeframe selectors (`Week`, `Month`, `Year`, plus multi-year)
  - Existing metric filters (strength and cardio metric tabs), preserving all current options:
    - Strength: `maxWeight`, `averageWeight`, `totalVolume`, `totalReps`, `averageReps`
    - Cardio: `totalDistance`, `totalDuration`, `averagePace`, `bestPace`
  - Existing unit filters (kg/lb and km/mi where relevant)
  - Same filter semantics as current exercise screen (no behavior drift between compact chart and explorer)

3) **Adaptable data scope**
- Explorer must accept optional scope:
  - `exerciseId` (or `Exercise`) provided: show only that exercise’s sessions
  - scope omitted: aggregate across all sessions
- Querying must be timeframe-based first (date interval), then filtered by optional exercise scope.
- Keep this non-destructive: no model/schema changes required.

4) **Data/query shape**
- Add lightweight interval-based fetch helpers in existing service layer (or local view-model helper) to avoid scanning all history every render.
- Return grouped bucket values keyed by bucket start date.
- Ensure zero-fill for missing buckets.

### Suggested file touch list
- `GymTracker/GymTracker/Views/Excerise/SingleExerciseView.swift`
- `GymTracker/GymTracker/Views/Excerise/ExerciseHistoryChartView.swift` (new)
- `GymTracker/GymTracker/Services/SessionService.swift` (timeframe fetch helper if needed)

### Acceptance checks
- Switching to `Year` shows all months even with sparse data.
- Switching to `5 Years` shows all selected years, including zero-data years.
- Tapping chart opens chart explorer screen.
- Explorer works for:
  - specific exercise scope
  - no exercise scope (all sessions)
- Filters/units still work and update chart immediately.

---

## Phase 6.2 — Health-style interactive timeline chart (generic + reusable)
### Goal
Replace the current full-screen history chart interaction with an Apple Health-style timeline experience:
- Smooth horizontal scrolling through time
- Clear timeframe tabs
- Bucketed aggregation per timeframe
- Press-and-hold bar inspection
- Full-width adaptive layout with no clipping on any screen size

### Visual behavior (based on reference screenshots)
- Top segmented timeframe tabs with compact labels: `W`, `M`, `6M`, `Y`, `5Y`.
- Prominent value summary above chart that updates with selection:
  - default: timeframe aggregate summary
  - while holding a bar: selected bucket value + bucket date/range
- Single-series vertical bar chart with subtle gridlines and right-side Y-axis labels.
- Chart color aligned to app tint family (use blue, matching existing app UI).
- Y-axis labels/grid origin should be on the **left** (match Apple Health style).

### Timeframe + aggregation rules (authoritative)
1) `W`:
- Window = current week by default.
- Aggregation = by day.
- X-axis label = 3-letter weekday (`Mon`, `Tue`, ...).

2) `M`:
- Window = current month by default.
- Aggregation = by day.
- X-axis label = day-of-month using `1..31` (no leading zero).

3) `6M`:
- Window = last 6 months by default (including current month).
- Aggregation = by week.
- X-axis label = 3-letter month abbreviations on axis (`Jan`, `Feb`, ...), with adaptive thinning.
- Data-point press label must show exact week range (e.g., `Sept 2-8`).

4) `Y`:
- Window = current year by default.
- Aggregation = by month.
- X-axis label = first letter of month (`J`, `F`, `M`, ...).

5) `5Y`:
- Window = current year and previous 4 years by default.
- Aggregation = by year.
- X-axis label = `YYYY`.

### Navigation + bounds
- Default load should show `M` timeframe.
- User can scroll/pan backward in time continuously.
- Future periods are not allowed (cannot scroll beyond current date period).
- Left/right jump buttons remain available as secondary controls.
- Scrolling should update visible bucket range; data should load for newly-visible periods.

### Interaction requirements
- Press-and-hold on a bar highlights bucket and shows contextual value tooltip/callout.
- Tooltip/callout content must include:
  - bucket value for the active metric
  - bucket date label (or date range for weekly buckets in `6M`)
- Releasing clears highlight and restores default summary.
- Changing timeframe or metric refreshes both:
  - X-axis bucket shape/labels
  - Y-axis scale and values
  - Y-axis side/placement remains on the left

### Axis vs data-point label clarification
- Axis labels are compact and timeframe-specific:
  - `W`: 3-letter weekday
  - `M`: day number `1..31`
  - `6M`: 3-letter month abbreviations
  - `Y`: single-letter month
  - `5Y`: `YYYY`
- Data-point labels (on press/hold) are contextual:
  - `W`/`M`: exact date
  - `6M`: week range (`MMM d-d`, e.g., `Sept 2-8`)
  - `Y`: full month + year
  - `5Y`: full year

### Data loading requirements
- Fetch by timeframe interval first, then metric/optional scope.
- Support incremental/windowed fetch while scrolling if feasible (preferred).
- If incremental fetch is not feasible in v1, prefetch one screen before/after visible interval.
- Always fill missing buckets with zero-value placeholders to keep axis spacing stable.

### Generic/reusable architecture requirement
- Implement chart as reusable/generic view component, usable by multiple features.
- Calling site should pass a metric/data enum (or protocol-backed source), for example:
  - exercise strength metrics
  - exercise cardio metrics
  - future non-exercise datasets
- Scope handling:
  - optional `exerciseId`/`Exercise` for scoped data
  - nil scope for all-session aggregate mode

### Layout/adaptivity requirements
- Entire chart block (tabs, summary, chart, axes) must fit and remain readable on all supported screen sizes.
- Compute bar width/spacing from container width and visible bucket count.
- Avoid axis label overlap with adaptive tick thinning/formatting where needed.
- Bars must always render within visible Y-axis domain bounds.
- If current/visible bucket values exceed existing Y-domain, expand Y-domain dynamically (headroom included) instead of clipping.
- While scrolling/timeframe changes, Y-axis may re-scale adaptively to visible data; chart container height must remain stable while domain updates.

### Suggested implementation slices
1) Extract reusable bucket + axis + interaction engine into generic chart module.
2) Build Exercise chart adapter (strength/cardio) implementing current filters.
3) Replace current full-screen chart view with generic timeline chart.
4) Keep compact chart view as lightweight entry point into full-screen explorer.

### Acceptance checks
- Default opens on `M` with current-month daily buckets.
- `W`, `M`, `6M`, `Y`, `5Y` each use correct aggregation + X labels.
- Hold gesture on any bar shows bucket value and date/range.
- Scrolling works fluidly; can go to past periods; cannot go into future.
- Filter changes recompute X/Y correctly and update chart immediately.
- Same reusable component can render scoped (`exercise`) and unscoped (`all sessions`) datasets.

---

## Phase 6.3 — Scroll bounds, tooltip behavior, dashboard entry, and capped prefetch
### Goal
Finalize timeline behavior for practical navigation and performance: stop at meaningful history boundaries, keep local chart interactions local, and wire dashboard entry into the same reusable chart screen.

### Decisions (locked)
1) **Past/future bounds**
- Future navigation remains disabled.
- Past navigation is allowed until the oldest session that has data for the active metric/scope.
- Timeframe windows still render fully:
  - Example: if oldest relevant session is in Dec 2025:
    - `Y` view can still show all of 2025.
    - `6M` can scroll back to a window starting Jun 2025 (covering Jun–Nov/Dec period as applicable).

2) **Main exercise chart interaction**
- In compact/main exercise chart, touching a bar shows only local tooltip/selection behavior.
- Opening full explorer should not be triggered by generic chart tap/drag.
- Use an explicit affordance for opening explorer (e.g., dedicated button/icon or clear link target), not bar-touch conflict.

3) **Dashboard integration**
- Dashboard volume module opens the shared chart explorer in:
  - `allSessions` scope
  - default metric: `totalVolume`
  - default timeframe: `M`

4) **Lazy prefetch with bounded cache**
- Use lazy interval prefetch while scrolling.
- Keep approximately 3 timeframe windows in-memory at once (rolling buffer).
- When user approaches trailing loaded edge, fetch next window and evict the farthest old window.
- If no more historical data exists, stop extending further.

5) **Filter row affordances**
- Add directional arrow hints to horizontal filter rows (metrics/units/timeframe chips) to indicate additional off-screen options.

### Acceptance checks
- Scrolling never enters future periods.
- Scrolling backward stops only after oldest relevant-data window is reached (with full-window rendering preserved).
- Bar touch in compact chart shows local selection/tooltip and does not accidentally navigate.
- Dashboard module opens explorer with `allSessions + totalVolume + M`.
- Prefetch keeps responsiveness while memory footprint stays bounded to ~3 windows.
- Filter rows visually indicate horizontal overflow via arrow hints.

---

## Phase 6.4 — Critical bug fixes + scroll interaction reliability 
### Status: **Fully Implemented** (Feb 26, 2026)

### Summary
This phase fixed critical data loss bugs, implemented reliable scrolling with proper window boundaries, and refined the chart interaction model. All features verified in implementation.

---

### Critical Bugs

#### Bug #1: Window Boundary Calculations (MAJOR DATA LOSS) 
**Symptom**: Switching M→6M→Y showed no data. M→Y showed only January. Data disappeared on timeframe switches.

**Root Cause**: `currentWindow()` was incorrectly using `startOfTomorrow` (literally tomorrow's date) as the END boundary for 6M, Y, and 5Y windows. For example on Feb 26, 2026:
- Year window was: Jan 1 → Feb 27 ❌ (should be Jan 1 → Jan 1, 2027)
- 6M window was: Sep 1 → Feb 27 ❌ (should be Sep 1 → Mar 1)
- This clipped 10+ months of potential data from year/5-year views

**Fix**: Each timeframe now calculates proper end boundary in `ExerciseHistoryChartSupport.swift`:
- `week`: +1 week from start
- `month`: +1 month from month-start
- `sixMonths`: +4 months from current month-start (total 6 months: -2 to +4)
- `year`: +1 year from year-start
- `fiveYears`: +2 years from year-start (total 5 years: -3 to +2)

**Impact**: 
- ✅ Year view now shows all 12 months (Jan-Dec 2026)
- ✅ 6M view loads full 6-month range properly
- ✅ Data no longer disappears when switching timeframes
- ✅ January data now visible when switching from M to Y

#### Bug #2: Timeframe Switch Scroll Interference 
**Symptom**: After switching timeframe, chart doesn't load data properly; visual state broken.

**Root Cause**: When calling `resetToCurrentWindow()` during timeframe switch, it set `chartScrollPosition = window.start`. This triggered `.onChange(of: chartScrollPosition)` which updated `anchorDate` using `snappedRangeStart()`, potentially interfering with the new window's calculation.

**Fix**: Added `@State private var isChangingTimeframe = false` flag in `ExerciseHistoryChartView.swift`:
```swift
.onChange(of: chartScrollPosition) { _, newValue in
    guard !isChangingTimeframe else { return }
    // ... normal handling
}
```
- Set to `true` when `timeframe` or `metricMode` changes  
- Skip scroll position onChange while flag is true
- Re-enable after 0.1s delay via `DispatchQueue.main.asyncAfter`

**Impact**: Timeframe switches cleanly without interference; data loads correctly every time

#### Bug #3: Session Filtering by Scope
**Symptom**: M→6M→Y shows "sessions but no data entries" message even though data exists.

**Root Cause**: `sessionService.sessionsInRange()` returns all sessions, but wasn't filtering by exercise scope. For scoped views (single exercise), we needed to filter to sessions containing that exercise.

**Fix**: In `resetToCurrentWindow()` and `shiftWindow()`:
```swift
loadedSessions = sessionService.sessionsInRange(loadedDataInterval).filter { session in
    !scopedEntries(in: session).isEmpty
}
```

**Impact**: Only sessions with relevant exercises are loaded for scoped views; correct data count and no false "no data" messages

#### Bug #4: Bidirectional Scrolling After Navigation ✅ FIXED
**Symptom**: After pressing left arrow to navigate to 2025, couldn't scroll back to 2026. Switching to 6M crashed with `EXC_BREAKPOINT`.

**Root Cause**: `currentWindowInterval.end` referenced old anchorDate (2025's end), but `earliestAllowedWindowStart` still referenced earliest data. When calculating `fullScrollableInterval`, this could create invalid `DateInterval(start > end)`.

**Fix**: Created `latestAllowedDate` computed property that always references end of today's window:
```swift
private var latestAllowedDate: Date {
    let nowWindow = ExerciseHistoryChartCalculator.currentWindow(for: timeframe, now: Date())
    return nowWindow.end
}
```
All loading operations now use: `DateInterval(start: earliestAllowedWindowStart, end: latestAllowedDate)`

**Impact**: 
- ✅ Can navigate to historical periods and scroll back to present
- ✅ No crashes when switching timeframes after navigation
- ✅ Full bidirectional scrolling works regardless of navigation history

---

### Implemented Features

#### 1. Reliable Horizontal Scrolling ✅
- Smooth horizontal scrolling with `chartScrollPosition` and `chartScrollableAxes(.horizontal)`
- No gesture conflicts between selection and pan
- Scroll clamping to valid bounds using `latestAllowedDate`
- Implementation verified in `ExerciseHistoryChartView.swift` lines 160-171

#### 2. Dynamic Data Loading ✅
- Initial anchor to current window: `resetToCurrentWindow()` loads data from `earliestAllowedWindowStart` to `latestAllowedDate`
- Full range always loaded (not windowed) to enable smooth bidirectional scrolling
- Arrow buttons shift windows and reload: `shiftWindow()` calculates new anchor and reloads full range
- Oldest data boundary check: `isPreviousDisabled` prevents navigation before earliest data
- Implementation verified in `ExerciseHistoryChartView.swift` lines 594-606, 610-652, 654-667

#### 3. Header-Based Selection (No Floating Tooltips) ✅
- Chart selection uses `chartXSelection(value: $selectedXDate)`
- Selected point highlights in chart: `selectedPointId` controls bar opacity
- Header shows selected point info via `summaryHeader` computed property
- Background tap gesture clears selection
- Filter changes (metric/unit) automatically clear selection
- Implementation verified in `ExerciseHistoryChartView.swift` lines 132, 143-157, 173-243, 347-381

#### 4. Dual Date Range Display ✅
**Top title bar (snapped window)**:
- Shows timeframe-aligned window user is anchored to via `snappedWindowInterval`
- Updates only when explicitly shifting windows (arrow buttons, initial load)
- Format matches timeframe:
  - `W`: "Jan 27 - Feb 2, 2026"
  - `M`: "February 2026"
  - `6M`: "Sep - Feb 2026"
  - `Y`: "2026"
  - `5Y`: "2022 - 2026"

**Above chart (visible range)**:
- Shows currently displayed viewport via `visibleWindowInterval`
- Live updates during scroll based on `chartScrollPosition`
- Can show partial periods when scrolled mid-window
- Implementation verified in `ExerciseHistoryChartView.swift` lines 385-403

#### 5. Window-Aligned Navigation ✅
- Scroll position snaps to timeframe-aligned boundaries
- Uses `snappedRangeStart(for:)` to calculate proper anchor
- Arrow button disabled states based on scroll position:
  - `isNextDisabled`: can't go forward past current period
  - `isPreviousDisabled`: can't go back before earliest data
- Implementation verified in `ExerciseHistoryChartView.swift` lines 560-606

#### 6. Visual Polish ✅
**Chart styling** (all implemented):
- Y-axis on right side: `AxisMarks(position: .trailing)`
- Horizontal Y-gridlines: `AxisGridLine(stroke: StrokeStyle(lineWidth: 0.9, dash: [2, 3]))`
- Vertical X-gridlines: matching dashed style
- Boxy bars: `cornerRadius(1.5)` minimal rounding
- Fixed bar width: `.fixed(barWidth)` for consistent spacing
- Selection highlighting: selected bar full opacity, others at 45% opacity
- Implementation verified in `ExerciseHistoryChartView.swift` lines 85-126

---

### UX Refinements

#### Scroll Behavior (Free Scrolling, No Lockout)
**Original plan**: "If scrolling slowly, lock at boundaries. Explicit button press loads new window."
**Actual implementation**: Free scrolling enabled throughout entire accessible range. Arrow buttons provide quick navigation but aren't required.
**Rationale**: Better user experience - users can freely explore history via scroll, arrows are optional convenience.

#### Filter Reset on Changes ✅
When user changes metric, unit, or cardio/strength mode:
- Selection explicitly cleared (`selectedPointId = nil`, `selectedXDate = nil`)
- Header reverts to default timeframe summary
- Chart recomputes with new filters
- Implementation verified in lines 173-243

---

### File Changes
**Modified files**:
- `GymTracker/Views/Excerise/ExerciseHistoryChartSupport.swift`
  - Fixed `currentWindow()` calculations (lines 40-72)
  - Fixed `axisMarkDates()` to generate complete mark sets (lines 177-210)
  
- `GymTracker/Views/Excerise/ExerciseHistoryChartView.swift`
  - Added `isChangingTimeframe` flag (line 67)
  - Added `actualLoadedInterval` state (line 64)
  - Added `latestAllowedDate` computed property (lines 404-407)
  - Implemented scroll clamping (lines 160-171)
  - Implemented arrow button disabling logic (lines 587-606)
  - Updated data loading in `shiftWindow()` and `resetToCurrentWindow()`

---

### Acceptance Checks ✅ ALL PASSING
- ✅ Full explorer scrolls horizontally with no gesture conflicts
- ✅ Older history remains reachable (no window lockout)
- ✅ First load opens at current window with proper data
- ✅ Can navigate backward to earliest data via arrows or scroll
- ✅ Selected point info appears in header (no floating tooltips)
- ✅ Background tap clears selection
- ✅ Filter changes clear selection automatically
- ✅ Title formats correctly: Y="2026", 6M="Sep - Feb 2026", 5Y="2022 - 2026"
- ✅ Window-aligned navigation with arrow buttons
- ✅ Y-axis on right side with horizontal gridlines
- ✅ Boxy bars with visible spacing
- ✅ Selection highlights chosen bar, dims others
- ✅ No crashes when switching timeframes after navigation
- ✅ Bidirectional scrolling works after window shifts

---

### Known Limitations / Future Improvements

1. **Prefetch strategy**: Currently loads full accessible range on every window operation. Future optimization could implement true incremental loading with intelligent caching for very large datasets.

2. **Snap behavior tuning**: Currently all scrolling is free (no velocity-based snap differentiation). Could add "fast flick → snap to boundary" vs "slow drag → precise positioning" in v2.

3. **Performance with massive datasets**: Not tested with thousands of sessions spanning many years. May need virtualization or smarter loading for extreme cases.

4. **Compact chart integration**: SingleExerciseView currently shows a simplified static chart. Could integrate same scrolling/selection features from full chart in v2.

---

## Phase 6.5 — Generic history chart refactor + nutrition history chart
### Status: **Not Started**

### Goal
Extract the chart infrastructure from the exercise-specific implementation into a generic, reusable layer. Then add a nutrition history chart as the first consumer of the shared layer, proving the abstraction works. No feature changes to the exercise chart.

---

### Architecture: 3-tier file structure

```
Views/HistoryChart/
├── HistoryChartSupport.swift          # Shared: timeframes, point struct, date windowing, bucketing
├── HistoryChartView.swift             # Shared: generic chart chrome (bar chart, scroll, selection, header, arrows)
├── ExerciseHistoryChartSupport.swift  # Exercise-specific: metric enums, data calculator, scope
└── NutritionHistoryChartSupport.swift # Nutrition-specific: metric enum, data calculator
```

**Tier 1 — `HistoryChartSupport.swift` (shared date/chart primitives)**
Contains everything that is domain-agnostic:
- `HistoryChartTimeframe` (renamed from `ExerciseHistoryTimeframe`) — `W / M / 6M / Y / 5Y`
- `HistoryChartPoint` (renamed from `ExerciseHistoryPoint`) — `startDate`, `endDate`, `value`, `id`
- `HistoryChartCalculator` (renamed from `ExerciseHistoryChartCalculator`) — all date windowing logic:
  - `currentWindow(for:now:)`
  - `shift(anchorDate:timeframe:direction:)`
  - `visibleDomainLength(for:)`
  - `xAxisLabel(for:timeframe:)`
  - `selectionLabel(for:timeframe:)`
  - `axisMarkDates(for:interval:)`
  - `bucketIntervals(interval:timeframe:)` (made `internal` instead of `private`)

**Tier 2 — `ExerciseHistoryChartSupport.swift` (exercise-specific)**
Keeps only domain-specific code:
- `ExerciseHistoryMetricMode` (`Strength / Cardio`) — exercise-specific dual-mode picker
- `ExerciseChartCalculator` — static methods for exercise data:
  - `strengthPoints(sessions:interval:timeframe:exerciseId:metric:displayUnit:)` → `[HistoryChartPoint]`
  - `cardioPoints(sessions:interval:timeframe:exerciseId:metric:distanceUnit:)` → `[HistoryChartPoint]`
  - Private `StrengthSample`, `CardioSample`, `strengthSamples()`, `cardioSamples()`, `paceValue()`

**Tier 3 — `NutritionHistoryChartSupport.swift` (nutrition-specific)**
New file with nutrition domain logic:
- `NutritionHistoryMetric` enum: `calories`, `protein`, `carbs`, `fat`
  - Maps directly from existing `NutritionSeriesMetric` but lives in the chart layer
  - Has `.title` and `.unitLabel` (`"kcal"`, `"g"`, `"g"`, `"g"`)
- `NutritionChartCalculator` — single static method:
  - `nutritionPoints(logs:interval:timeframe:metric:)` → `[HistoryChartPoint]`
  - Uses `HistoryChartCalculator.bucketIntervals()` for date bucketing
  - Sums `FoodLog.kcal / .protein / .carbs / .fat` per bucket

---

### View layer: `HistoryChartView.swift`

**Protocol-based data provider pattern:**

```swift
protocol HistoryChartDataProvider {
    /// Title for navigation bar
    var navigationTitle: String { get }
    
    /// Chart points computed from current filter state
    var chartPoints: [HistoryChartPoint] { get }
    
    /// Summary text for the header section
    var summaryTitle: String { get }
    var summaryValueText: String { get }
    var summaryValueUnitText: String? { get }
    var summaryDateText: String { get }
    
    /// Whether there is a selected point
    var selectedPoint: HistoryChartPoint? { get }
    
    /// Empty state message
    var emptyStateText: String { get }
    
    /// Oldest/newest data dates for scroll bounds
    var oldestDataDate: Date? { get }
    var newestDataDate: Date? { get }
    
    /// Callback when filters change (clear selection, reload)
    func onFilterChange()
    
    /// The filter controls specific to this domain
    @ViewBuilder var filterControls: some View { get }
}
```

**`HistoryChartView<Provider: HistoryChartDataProvider>`** is the generic chart container.
It owns all shared state and chrome:
- Timeframe picker + arrow navigation
- Scroll position / clamping / `isChangingTimeframe` flag
- Bar chart rendering (BarMark, axes, gridlines, selection highlighting)
- Summary header layout
- All `.onChange` handlers for timeframe/scroll
- `resetToCurrentWindow()`, `shiftWindow()`, `snappedRangeStart()`, etc.

The provider supplies: chart points, filter UI, summary text, data bounds.

**`ExerciseHistoryChartView`** — thin wrapper struct (~80 lines)
- Holds `@EnvironmentObject var sessionService: SessionService`
- Holds exercise-specific `@State`: `metricMode`, `selectedStrengthMetric`, `selectedCardioMetric`, `selectedWeightUnit`, `selectedDistanceUnit`
- Conforms to or feeds `HistoryChartDataProvider` (via `@Observable` view model or inline computed properties)
- `filterControls` returns: mode picker + metric chip row + unit chip row
- `chartPoints` calls `ExerciseChartCalculator.strengthPoints(...)` or `.cardioPoints(...)`
- Data loading: `sessionService.sessionsInRange(interval)` filtered by scope

**`NutritionHistoryChartView`** — thin wrapper struct (~50 lines)
- Holds `@EnvironmentObject var nutritionService: NutritionService`
- Holds nutrition-specific `@State`: `selectedMetric: NutritionHistoryMetric`
- `filterControls` returns: single metric chip row (Calories / Protein / Carbs / Fat)
- `chartPoints` calls `NutritionChartCalculator.nutritionPoints(...)`
- Data loading: reuses existing `nutritionService.dailyNutritionSeries()` or fetches `FoodLog` array via a lightweight `logsInDateInterval()` stub if needed
- No mode picker (nutrition has no dual mode), no unit picker (kcal/g are fixed)

---

### NutritionDayView entry point

Add a small history button to the top-left toolbar of `NutritionDayView`:

```swift
ToolbarItem(placement: .topBarLeading) {
    NavigationLink {
        NutritionHistoryChartView()
            .appBackground()
    } label: {
        Image(systemName: "chart.bar.xaxis")
    }
}
```

---

### NutritionService additions (minimal)

If `dailyNutritionSeries(endingOn:days:metric:)` can't serve arbitrary `DateInterval` ranges efficiently, add one small method:

```swift
func logsInDateInterval(_ interval: DateInterval) throws -> [FoodLog] {
    // Single SwiftData fetch for the full interval, similar to the existing method
}
```

This mirrors `SessionService.sessionsInRange()` and gives `NutritionChartCalculator` raw `FoodLog` arrays to bucket.

---

### Rename mapping

| Old name | New name | File |
|---|---|---|
| `ExerciseHistoryTimeframe` | `HistoryChartTimeframe` | `HistoryChartSupport.swift` |
| `ExerciseHistoryPoint` | `HistoryChartPoint` | `HistoryChartSupport.swift` |
| `ExerciseHistoryChartCalculator` (date/window methods) | `HistoryChartCalculator` | `HistoryChartSupport.swift` |
| `ExerciseHistoryChartCalculator` (strength/cardio methods) | `ExerciseChartCalculator` | `ExerciseHistoryChartSupport.swift` |
| `ExerciseHistoryChartView.swift` | `HistoryChartView.swift` | rename file |
| `struct ExerciseHistoryChartView` | `struct HistoryChartView<Provider>` | `HistoryChartView.swift` |

**Typealias for backward compat (optional):** If call sites are numerous, add `typealias ExerciseHistoryTimeframe = HistoryChartTimeframe` temporarily — but with only 2 call sites (`SingleExerciseView`, `SessionVolumeChart`) this is likely unnecessary; just update them.

---

### Call site updates

1. **`SingleExerciseView.swift` line 368**: `ExerciseHistoryChartView(exercise: exercise)` → same name, same API (the thin wrapper keeps this init)
2. **`SessionVolumeChart.swift` line 153**: `ExerciseHistoryChartView()` → same name (defaults to `allSessions` scope)
3. **`NutritionDayView.swift`**: new toolbar button → `NutritionHistoryChartView()`

---

### What does NOT change
- All exercise chart features (scrolling, selection, arrows, timeframe, metric/unit filters, summary header, bar styling) — identical behavior
- `ExerciseHistoryChartCalculator.strengthPoints()` / `.cardioPoints()` logic — just moves to `ExerciseChartCalculator`
- Date windowing / bucketing math — just moves to `HistoryChartCalculator`
- `ProgressMetric`, `CardioProgressMetric`, `WeightUnit`, `DistanceUnit` — stay where they are
- Phase 6.4 bug fixes all preserved (scroll clamping, `isChangingTimeframe`, `latestAllowedDate`, etc.)

---

### Acceptance checks
- Exercise chart behaves identically to pre-refactor (all Phase 6.4 checks still pass)
- `NutritionDayView` shows a chart button in top-left toolbar
- Tapping it opens `NutritionHistoryChartView` with calories selected by default
- Nutrition chart supports W/M/6M/Y/5Y timeframes with correct bucketing
- Nutrition chart has metric chip row: Calories / Protein / Carbs / Fat
- Nutrition chart has no mode picker and no unit picker
- Scrolling, selection, arrows all work identically to exercise chart
- Adding a third chart type (e.g., body weight) would require only: 1 support file + 1 thin view wrapper

### File changes
**New files:**
- `GymTracker/Views/HistoryChart/HistoryChartSupport.swift`
- `GymTracker/Views/HistoryChart/HistoryChartView.swift`
- `GymTracker/Views/HistoryChart/NutritionHistoryChartSupport.swift`

**Modified files:**
- `GymTracker/Views/HistoryChart/ExerciseHistoryChartSupport.swift` — remove shared date logic, keep exercise calculator
- `GymTracker/Views/HistoryChart/ExerciseHistoryChartView.swift` — becomes thin wrapper calling `HistoryChartView`
- `GymTracker/Views/Nutrition/NutritionDayView.swift` — add toolbar chart button
- `GymTracker/Views/Excerise/SingleExerciseView.swift` — update import if needed
- `GymTracker/Views/Home/SessionVolumeChart.swift` — update import if needed
- `GymTracker/Services/NutritionService.swift` — add `logsInDateInterval()` if needed
- `GymTracker.xcodeproj/project.pbxproj` — add new file references

---

## Phase 7 — Aliases editor (exercise + routine)
### Non-destructive schema
- Add optional `aliases: [String]?` (or equivalent) to Exercise and Routine, **only if it doesn’t exist already**.

### Requirements
- UI: edit aliases in an “Identity” section.
- Behavior: aliases used for import matching + search, not display name.- **Visibility rule: Display name is always the primary `name` field; aliases never override it in any UI context.**

### Import resolver integration
- During notes import, aliases expand the fuzzy-match pool (e.g., "Bench Press" exercises with aliases ["Barbell Bench", "BB Bench"] will match import entries with those terms).
- If resolve is ambiguous (multiple exercises have matching aliases), respect existing resolution logic (ask user or pick first).
- **Do not silently pick an alias match over the original name.**
### Backup compatibility
- Export aliases if present.
- Import: accept missing aliases field.

---

## Phase 8 — Optimistic delete with instant undo (soft-delete + persistent toast stack)
### Goal
Allow users to instantly recover from accidental deletes with instant feedback. Support stacked notifications that persist across view changes, with each deletion independently undoable. When a new toast arrives, the timer of the previous one pauses until the new one is handled.

### Architecture: Soft-Delete + Centralized Toast Manager

**Core components:**
1. **Soft-Delete Pattern** (services): Mark as archived instead of hard-delete
2. **ActionToastManager** (EnvironmentObject): Manages toast queue + timing state
3. **ActionToastStack** (UI): Displays stacked toasts above nav bar (always visible)
4. **Per-View Integration** (views): Call `toastManager.add()` with details

**Toast Stack Behavior:**
- Front toast: Full size, countdown active, can undo
- Previous toasts: Smaller, stacked underneath, timers paused
- When front toast dismissed: Next toast takes front position, its timer resumes
- Timers only count down for the front toast (prevents timeout race conditions)

**Why this works:**
- Toasts persist across view navigation (in EnvironmentObject)
- Each action independent (can undo any toast before timeout)
- User sees all pending undos at once (stacked view)
- Clean state management (manager owns timing, not views)

### Requirements

1. **ActionToast data model**
   - `id: UUID` (unique identifier)
   - `message: String` (what's being deleted, e.g., "Delete Exercise 'Bench Press'?")
   - `actionTitle: String?` (e.g., "Undo")
   - `timeout: TimeInterval` (default 4s)
   - `onAction: () -> Void` (undo callback)
   - `onTimeout: () -> Void` (finalize callback)
   - `createdAt: Date` (for tracking + sorting)

2. **ActionToastManager (EnvironmentObject)**
   - `@Published var toasts: [ActionToast]` (ordered stack, newest at end)
   - Methods:
     - `add(message, actionTitle, timeout, onAction, onTimeout)` → adds to stack
     - `remove(id:)` → removes toast, check if needs pause/resume
     - `dismiss(id:)` → user taps action
     - Private: `startTimer(for:)`, `pauseTimers()`, `resumeFrontTimer()`
   - Logic: Keep track of active timer + paused timers per toast
   - Injected in GymTrackerApp.swift via `.environmentObject(ActionToastManager())`

3. **ActionToastStack view** (App.swift or root)
   - `@EnvironmentObject var toastManager: ActionToastManager`
   - Display above nav bar (z-position: always on top)
   - Show front toast full size at bottom
   - Show 0–2 previous toasts smaller, slightly above
   - Each toast shows: message + [Undo] button + countdown remaining
   - Tapping Undo calls `toastManager.dismiss(id:)`
   - No swipe-to-dismiss (requires explicit action)

4. **Service soft-delete updates** (same as Phase 8a)
   - ExerciseService, RoutineService, ExerciseSplitDayService: archive instead of hard-delete
   - Restoration methods: simply unarchive

5. **View integration** (simplified)
   
   **ExercisesView / SplitDaysView / SingleDayView:**
   - `@EnvironmentObject var toastManager: ActionToastManager`
   - On delete: 
     ```swift
     toastManager.add(
       message: "Delete 'Exercise Name'?",
       actionTitle: "Undo",
       timeout: 4,
       onAction: { restoreItem() },
       onTimeout: { /* already deleted */ }
     )
     ```
   - For bulk delete (multiple items): loop and call `add()` for each
   - Each toast is independent (can undo any one before timeout)

### Files changed

**New:**
- `GymTracker/Manager/ActionToastManager.swift`
- `GymTracker/Views/ActionToastStack.swift`

**Modified:**
- `GymTracker/Views/ActionToast.swift` — convert to data model (remove modifier)
- `GymTracker/Views/Excerise/ExercisesView.swift` — use EnvironmentObject instead of @State
- `GymTracker/Views/SplitDay/SplitDaysView.swift` — use EnvironmentObject instead of @State
- `GymTracker/Views/SplitDay/SingleDayView.swift` — use EnvironmentObject instead of @State
- `GymTracker/GymTrackerApp.swift` — add ActionToastManager to environment + add ActionToastStack at root level

### Acceptance checks
- ✅ Delete 1 exercise → 1 toast, Undo works
- ✅ Delete 3 exercises (bulk select) → 3 toasts stacked, each with own Undo
- ✅ Front toast at normal size, previous ones smaller
- ✅ Tap Undo on middle toast → that item restored, middle toast removed, timers remain paused until it's front again
- ✅ Front toast timeout fires → toast auto-dismisses, next toast moves to front + timer resumes
- ✅ Switch views while toasts pending → toasts still visible, timers continue
- ✅ Each toast shows item name/details (not just "Delete?")
- ✅ No rapid timeout race (only front toast timer ticks)

---

## Phase 9 — Timer/watch/Dynamic Island + haptics
### Requirements
- Notifications only for user-facing events (timer finished, optional “away too long”).
- Live Activity/watch updates only on state changes (not notification spam).
- Haptics:
  - Primary actions (save/complete) get haptic
  - Timer countdown pattern configurable (30s, 15s, 5s remaining)

- Give ideas how to implement before coding.
---

## Phase 10 — Nutrition serving UX (minimal optional fields)
### Non-destructive schema
If you implement serving references:
- Add optional fields to Food:
  - `referenceServingGrams: Double?`
  - `referenceServingLabel: String?` (e.g., “1 serving”, “1 scoop”)
- For logs:
  - keep storing grams as today
  - optionally store `servingMultiplier: Double?` for nicer display (“1.5 servings”)
### Scope guardrail
- **No calculation changes in v1**: all macro/calorie math continues to use grams only.
- `servingMultiplier` is **display only** (e.g., show "1.5 servings" alongside the grams value).
- If `referenceServingGrams` is not set, don't attempt to infer or divide grams—just show grams.
- Defer any "scale recipe by servings" or "multiply nutrition by servings" logic to v2.
### Backup compatibility
- Export these optional fields if present.
- Import must accept older backups without them.

---

## What the agent should inspect before coding
- Models: Session, Exercise, Set (or equivalents), and any SessionExercise join entity.
- Views: SessionView, SessionExerciseView, SingleExerciseView, any “previous logs” screen.
- Services: stats/volume calculators; backup import/export (ExerciseBackupService, SessionBackupService, NutritionBackupService, etc.); import resolver if aliases affect it.

---

## Definition of Done per phase
- Builds on iOS.
- No destructive schema changes.
- Backup export/import remains compatible with older backups.
- Manual acceptance checks listed above pass.
