
important files and folders
- ./GymTracker/Models/Nutrition, all models for nutrition should go in this folder
- ./GymTracker/Services/NutritionService.swift, all nutirtion SwiftData actions should be in this class
- ./GymTracker/Views/Nutrition, all views for nutirtion should go in this folder
- a new DashboardModule should be made for opening the required view. edit DashboardService.swift

---

## Goal

Add a **Nutrition** feature to GymTracker with:

* Foods database
* Food logging (standalone entries like snacks)
* Optional preset meals (templates) that can be logged quickly
* A **daily view** with:

  * date display
  * left/right arrows to move day
  * calendar button to jump to any date

Keep it simple.

---

## Data model (SwiftData)

### 1) Food

**Purpose:** nutritional definition of a food item.

Fields:

* `id: UUID`
* `name: String`
* `brand: String?` (optional)
* `referenceLabel: String?` (optional UI label like “1 scoop”, “1 slice”)
* `gramsPerReference: Double` (required, > 0)
* `kcalPerReference: Double`
* `proteinPerReference: Double`
* `carbPerReference: Double`
* `fatPerReference: Double`
* `createdAt: Date`
* `updatedAt: Date`

Derived helpers (computed, not stored):

* `kcalPerGram = kcalPerReference / gramsPerReference`
* same for macros per gram

Validation:

* gramsPerReference must be > 0
* all nutrition values must be >= 0

### 2) FoodLogCategory (enum)

* breakfast, lunch, dinner, snack, other
  Store as `Int` (`categoryRaw`) in SwiftData.

### 3) Meal (template)

**Purpose:** reusable preset. Not history.

Fields:

* `id: UUID`
* `name: String`
* `createdAt: Date`
* `updatedAt: Date`
  Relationship:
* `items: [MealItem]` (cascade delete)

### 4) MealItem (template items)

Fields:

* `id: UUID`
* `order: Int`
* `grams: Double` (canonical)
  Relationships:
* `meal: Meal`
* `food: Food`

### 5) MealEntry (history group header)

**Purpose:** represents “user logged a preset meal at a time” so you can group items in the UI.

Fields:

* `id: UUID`
* `timestamp: Date`
* `categoryRaw: Int`
* `note: String?` (optional)
  Relationship:
* `templateMeal: Meal?` (optional reference to the template; do NOT cascade delete history if template changes)

### 6) FoodLog (history row)

Fields:

* `id: UUID`
* `timestamp: Date`
* `categoryRaw: Int`
* `grams: Double` (canonical amount eaten)
* `note: String?` (optional)
  Relationships:
* `food: Food`
* `mealEntry: MealEntry?` (nullable; set when created from logging a preset)

Optional (nice, still simple):

* `displayQuantity: Double?` (e.g., 2)
* `displayUnitLabel: String?` (e.g., “scoop”)
  This lets UI show “2 scoops” while storing grams for totals.

Delete rules:

* `Meal.items` cascade to `MealItem`
* `MealEntry` cascade to its `FoodLog`s (if you set inverse relationship)
* Deleting `Meal` template must NOT delete `MealEntry` history (don’t cascade from templateMeal)
* Deleting a `Food` should be prevented if logs exist (or implement “archive food” instead)

---

## Computation rules

All daily totals come from **FoodLog** rows for that date:

* `kcal = grams * food.kcalPerGram`
* protein/carbs/fat same pattern

Grouping:

* If `foodLog.mealEntry == nil` → standalone (snack / quick add)
* If `foodLog.mealEntry != nil` → grouped under that mealEntry in UI

---

## Screens + UI requirements

### A) Nutrition Day View (main screen)

Top bar:

* Left arrow button: previous day
* Center: formatted date (e.g., “Feb 23, 2026”)
* Right arrow button: next day
* Calendar button (icon) to open date picker sheet

Body:

1. Daily summary header:

   * Total calories for day
   * Optional macro totals (P/C/F)
2. Sections by category in this order:

   * Breakfast, Lunch, Dinner, Snack, Other
3. Each section contains:

   * Standalone FoodLogs for that category (mealEntry == nil)
   * MealEntries for that category (each expandable/collapsible)
4. Floating or bottom buttons:

   * “Add Food”
   * “Log Meal” (optional if you implement meals now; can be second button)

Interactions:

* Tap FoodLog row → edit sheet (change grams, time, category, note)
* Swipe delete on FoodLog
* Tap MealEntry header → expand/collapse
* Swipe delete MealEntry → deletes all its FoodLogs

Date behavior:

* Store `selectedDate: Date` (normalized to start-of-day for queries)
* Arrows update `selectedDate` by ±1 day
* Calendar button opens a DatePicker; selecting sets `selectedDate`

### B) Add Food screen

Simple form:

* Name
* Brand (optional)
* Reference label (optional; “1 scoop”)
* Grams per reference (required)
* Calories per reference
* Protein/Carb/Fat per reference
  Save creates Food.

### C) Add Food Log flow

From day view:

* Pick a Food (search list)
* Enter either:

  * grams directly, OR
  * quantity + uses `gramsPerReference` (if you implement displayQuantity)
* Choose category (default based on time)
* Choose time (default now but date pinned to selectedDate)
  Save creates FoodLog.

### D) Meals (templates) screens (optional but recommended)

1. Meals list

   * list of Meal templates
   * tap to view/edit
   * “Create Meal” button
2. Meal editor

   * meal name
   * add foods with grams
   * reorder items

“Log Meal” action from Nutrition Day View:

* user picks template meal
* choose category + time
* create MealEntry(timestamp, category, templateMeal=selectedMeal)
* for each MealItem:

  * create FoodLog(food, grams=item.grams, timestamp, category, mealEntry=createdMealEntry)

---

## SwiftData querying requirements

### For a given selected date:

Define:

* `dayStart = startOfDay(selectedDate)`
* `dayEnd = dayStart + 1 day`

Fetch:

* all `FoodLog` where `timestamp >= dayStart && timestamp < dayEnd`
* all `MealEntry` where `timestamp >= dayStart && timestamp < dayEnd`

Build view models in memory:

* `standaloneLogs = foodLogs.filter(mealEntry == nil)`
* `entries = mealEntries.map { entry in entryLogs = foodLogs.filter(mealEntry.id == entry.id) }`

Sort:

* Within category:

  * MealEntries by timestamp
  * Standalone logs by timestamp
* MealItem logs inside entry sorted by original MealItem order if possible (otherwise timestamp)

---

## Minimal implementation order (do it in this order)

### Phase 1 (ship fast: foods + logs)

1. Add SwiftData models: `Food`, `FoodLog`, `FoodLogCategory`
2. Build Nutrition Day View with date arrows + calendar picker
3. Add Food CRUD (create + list + search)
4. Add FoodLog create/edit/delete
5. Daily totals + category sections

### Phase 2 (presets)

6. Add `Meal` + `MealItem`
7. Meals list + editor
8. “Log Meal” generates multiple FoodLogs

### Phase 3 (nice grouping)

9. Add `MealEntry`
10. Update “Log Meal” to create MealEntry and link FoodLogs
11. Update UI to render MealEntry headers with expandable children

(You can swap phase 2 and 3 if you want grouped meals from day one.)

### Phase 4 (Polish + Data Safety + UX speed)

Tell it to implement these, in this order:

## 4.1 Data safety (prevents breaking history)

1. **Archive foods instead of deleting**

* Add `Food.isArchived: Bool = false`
* Update Food picker/search to hide archived foods by default
* If a food has any `FoodLog` references, the “Delete” action should **archive** instead
* Still allow un-archiving from a “Archived Foods” section/screen

2. **Hard validation + clamping**

* Disallow saving:

  * `gramsPerReference <= 0`
  * `FoodLog.grams <= 0`
  * any macros/kcal < 0
* Use inline error messages in forms (don’t crash)

## 4.2 Fast logging UX (simple but huge win)

3. **Recent + Favorites**

* Add `Food.isFavorite: Bool = false`
* In “Add Food Log” picker:

  * Section 1: Favorites
  * Section 2: Recently logged (last 14 days, unique foods)
  * Section 3: All foods (search)
    This makes logging feel instant.

4. **Copy yesterday / repeat**

* On Nutrition day view: “Copy from yesterday”
* Behavior:

  * Copy standalone `FoodLog`s (mealEntry == nil) from previous day into selected day
  * Keep same categories, set timestamp to a default time (or preserve time-of-day but change date)
  * Do **not** duplicate MealEntries (keep it simple for now)

## 4.3 Editing + grouping polish

5. **MealEntry edit**

* Allow editing: time, category, note
* If MealEntry time/category changes, update all child FoodLogs to match (so grouping stays consistent)

6. **Undo for deletions (optional but nice)**

* If you already use swipe-to-delete, implement a simple undo toast/snackbar.
* If that’s too much, require a confirmation dialog.

## 4.4 Daily summary improvements

7. **Macro + calorie summary card**

* Show: calories + P/C/F totals
* Add a simple “remaining” line if you have targets (optional; if no targets, skip)

8. **Day navigation quality**

* Ensure selectedDate uses start-of-day consistently
* Calendar date picker jumps correctly and refreshes queries
* Arrows animate day change (optional)

---
### Phase 5 — Nutrition UI Cleanup (Single Log Flow + Clean Management)

## Goal

Clean up Nutrition UI so the main day view has **one single Log button**. Logging supports **Food** or **Meal template** from one flow, and allows creating new foods/meals inline. The top-right menu becomes a **Manage** area with a tab selector (**Foods / Meals**) for listing and editing.

---

## 5.0 UX rules

1. **Nutrition Day View** must have only **one primary action**: `Log`.
2. Logging must support:

   * logging a single food (snack/ad-hoc)
   * logging a meal template (creates MealEntry + child FoodLogs)
   * creating new food or meal template inside the flow, then selecting it
3. The top-right menu opens **Manage** (Foods / Meals tabs).
4. “No duplicate screens” means: **no duplicate add/log buttons on the day view**.
   It is OK for Picker and Manage to both show lists—**they serve different contexts**:

   * Picker = selection + quick-create
   * Manage = full CRUD + archive/unarchive + favorites

---

## 5.1 Nutrition Day View changes

### Replace bottom buttons

**Remove**:

* Add Food
* Log Food
* Log Meal

**Add**:

* One button: **Log** (bottom bar or floating action)

### Menu button behavior

Keep the menu icon. On tap, open a sheet:

* Title: **Manage**
* Segmented control at top: **Foods | Meals**
* Each tab includes search + list + add + edit

---

## 5.2 Unified Log flow

Tapping **Log** opens `LogSheet` (sheet with a NavigationStack).

### LogSheet layout

Top:

* Title: **Log**
* Cancel / Save
* Segmented control: **Food | Meal**

Shared fields (both modes):

* Category picker
* Time picker
* Note (optional)

Food mode fields:

* Food picker row (opens FoodPickerView)
* Grams input

Meal mode fields:

* Meal template picker row (opens MealPickerView)
* Optional: display meal totals preview

Save rules:

* Food mode: requires `selectedFood != nil && grams > 0`
* Meal mode: requires `selectedMeal != nil`

On Save:

* Food mode → create 1 `FoodLog`
* Meal mode → call `NutritionService.logMeal(template:)` → creates `MealEntry` + N `FoodLog` (linked to entry)

Defaults:

* category defaults to last used or time-of-day heuristic
* time defaults to now, but date pinned to selectedDate

---

## 5.3 Picker views (must support “create new”)

Both pickers live inside the LogSheet navigation stack and return a selection.

### FoodPickerView

* Search bar
* Sections in this order:

  1. Favorites
  2. Recent (unique foods) — **last 14 days**
  3. All foods (alphabetical)
* Primary action: **+ New Food**

  * Push `AddFoodView`
  * On successful save: auto-select the new food and pop back

**Archived rule (explicit):**

* Archived foods are **excluded** from Favorites, Recent, and All by default.
* If you want a way to log an archived food, it must be behind an explicit toggle:

  * `Show archived` (off by default).
    If off, archived never appears anywhere in the picker.

### MealPickerView

* Search bar
* List of meal templates
* Primary action: **+ New Meal Template**

  * Push `MealTemplateEditor`
  * On successful save: auto-select and pop back

---

## 5.4 Manage sheet (from menu button)

Menu button opens `ManageNutritionSheet` (sheet + NavigationStack).

### ManageNutritionSheet UI

Top:

* Title: **Manage**
* Segmented control: **Foods | Meals**

#### Foods tab

* Search bar
* List of foods (non-archived by default)
* Each row supports:

  * tap → edit food
  * favorite toggle (star)
  * archive action

Archived handling:

* Add a secondary section or toggle:

  * `Show archived` (off by default)
* Archived foods are shown only when enabled.
* From archived list, allow **unarchive**.

**Important delete rule (explicit):**

* Foods are **never hard-deleted**.
  The UI action is **Archive** (and Unarchive).
  (This avoids broken history and keeps behavior consistent.)

#### Meals tab

* Search bar
* List templates
* tap → edit template
* delete template allowed (does not affect history)

---

## 5.5 Service/API requirements (NutritionService.swift)

No new service files. Implement/adjust these functions.

### Creation contracts (explicit, no “fake success”)

Creation can fail due to validation. Use one of:

* `throws`, or
* optional return.

Pick one approach and apply consistently:

**Preferred (clean): use throws**

* `func createFood(...) throws -> Food`
* `func createMealTemplate(...) throws -> Meal`

Or if you want optional:

* `func createFood(...) -> Food?`
* `func createMealTemplate(...) -> Meal?`

**Do not use non-optional return without throws.**

### Required helper functions

* `fetchFoods(search: String?, includeArchived: Bool = false) -> [Food]`
* `fetchFavoriteFoods(includeArchived: Bool = false) -> [Food]`
* `fetchRecentFoods(days: Int = 14, includeArchived: Bool = false) -> [Food]`

  * recent = unique foods from logs in last N days, sorted by most recent log timestamp
* `toggleFavorite(food:)`
* `archiveFood(food:)` (sets `isArchived = true`)
* `unarchiveFood(food:)`

Logging:

* `addFoodLog(...)`
* `logMeal(template: Meal, ...) -> MealEntry`

Validation:

* Food: name non-empty, gramsPerReference > 0, nutrition values >= 0
* FoodLog: grams > 0

---

## 5.6 Model requirements (if not already done)

Food:

* `isArchived: Bool = false`
* `isFavorite: Bool = false`

FoodLog:

* keep canonical `grams`
* optional display fields are allowed, but not required

---

## 5.7 Acceptance checklist

1. Nutrition day view shows exactly **one** primary action: Log
2. LogSheet can log:

   * food (single FoodLog)
   * meal template (MealEntry + child FoodLogs)
3. Within LogSheet you can:

   * create a new Food and immediately select it
   * create a new Meal template and immediately select it
4. Menu button opens Manage with tabs:

   * Foods: search, favorite, archive/unarchive (no hard delete)
   * Meals: search, create, edit, delete template
5. FoodPicker excludes archived by default and uses **14-day** recent list
6. No duplicated “Add Food / Log Meal” buttons on the day view

---

# Phase 5 — Final Clarifications (Authoritative)

This section overrides any older/legacy Phase 5 checklist or flow wording in `NutritionImplementation.md`. If there are multiple checklists, **keep only this one** as the canonical Phase 5 acceptance checklist.

---

## A) Error/return contracts (consistency rule)

Any write that can fail due to validation or persistence **must not** return a non-optional value without error signaling.

### Required contracts

* `createFood(...)` → **throws** `Food` (preferred) OR returns `Food?`
* `createMealTemplate(...)` → **throws** `Meal` OR returns `Meal?`
* `logMeal(template:..., ...)` → **throws** `MealEntry` OR returns `MealEntry?`

**Preferred:** make them all `throws` for consistency.

Validation failures should throw a small typed error (e.g., `NutritionError.validation(String)`).

---

## B) Archived foods visibility + unarchive + logging (explicit)

Archived foods are hidden by default, but users must be able to reveal and use them.

### FoodPickerView (inside LogSheet)

* Add a `Show archived` toggle at the top of the list (near search / above sections).
* Default: OFF
* When OFF: archived foods do not appear in Favorites/Recent/All.
* When ON:

  * archived foods are included in lists (e.g., appear in All, and can appear in Recent/Favorites if applicable)
  * archived foods rows show an `Archived` badge + an `Unarchive` action (swipe or button)
  * selecting an archived food is allowed **only if** one of these is true:

    1. user unarchives it first (recommended UX), OR
    2. selection is allowed but Save will auto-unarchive on save
       (choose one approach and document it)

**Recommended (simple + consistent):**

* If user selects an archived food, show a small prompt:

  * “This food is archived. Unarchive to log?” → Unarchive + Continue
* Do not allow logging archived foods without unarchiving.

### Manage → Foods tab

* Same `Show archived` toggle at the top.
* Unarchive action available from archived list.

### Food deletion rule (unchanged)

* Foods are **never hard-deleted**. Only archive/unarchive.

---

## C) Selected food becomes archived while LogSheet is open (edge case)

Define behavior explicitly:

If `selectedFood.isArchived == true` at save time:

* Block save and show message: “Selected food is archived. Unarchive to log.”
* Provide action: `Unarchive` → then save proceeds.

(This prevents confusing silent failures.)

---

## D) MealTemplateEditor inside LogSheet: no-food guard (avoid dead-end)

When user chooses **Meal** mode and taps “+ New Meal Template”:

If there are **0 non-archived foods** available:

* Show an empty state:

  * “No foods yet”
  * Button: “Create Food”
* “Create Food” pushes `AddFoodView`
* After saving a Food:

  * return to MealTemplateEditor and allow adding items

Also define for archived-only scenario:

* If only archived foods exist:

  * show `Show archived` toggle in the food picker inside MealTemplateEditor
  * allow unarchive from there

---
Cool — the agent hasn’t actually done the Phase 7 “remove legacy flow” yet; it’s asking if you want it to. You do.

Copy/paste this to the agent as **Phase 7 instructions** (direct and unambiguous):

---
## Phase 6 — Nutrition Power Features (Non-breaking Additions Only)

This phase must **not** refactor or rename existing Nutrition models, relationships, screens, or service methods. It may only **add**:

* new models/fields (with safe defaults),
* new service methods,
* new UI views/sheets,
* small UI affordances on existing screens.

Do **not** change the unified Phase 5 Log/Manage flow.

---

# 6.0 Guardrails (must follow)

1. **No changes** to:

   * `Food`, `FoodLog`, `Meal`, `MealItem`, `MealEntry` schemas (except adding optional fields or safe-default fields)
   * existing fetch methods signatures (you may add overloads/new methods)
   * the unified `LogSheet` structure (you may add a “Quick Add” mode inside it, but don’t split flows)
2. All new persistence writes must be **throws** and show user-visible errors (reuse Phase 5 error alert pattern).
3. History integrity rules remain:

   * Foods are archived/unarchived only; never hard delete.
   * `grams` remains canonical for FoodLogs and MealItems.
4. If a feature cannot be implemented without restructuring, **skip it** for Phase 6.

---

# 6.1 Daily Targets (simple)

## Purpose

Allow users to set daily calorie + macro targets and show “remaining” in the day summary.

## Data model (new)

Create `@Model final class NutritionTarget` in `Models/Nutrition/`:

Fields:

* `id: UUID`
* `createdAt: Date`
* `updatedAt: Date`
* `calorieTarget: Double` (default 0)
* `proteinTarget: Double` (default 0)
* `carbTarget: Double` (default 0)
* `fatTarget: Double` (default 0)
* Optional future-proof (safe default):

  * `isEnabled: Bool` (default false)

Rules:

* Values must be `>= 0`
* Treat `0` as “unset” for that macro
* Only one active target record (use first-or-create pattern)

## Service (add-only)

In `NutritionService` add:

* `func getOrCreateTarget() throws -> NutritionTarget`
* `func updateTarget(calories: Double, protein: Double, carbs: Double, fat: Double, enabled: Bool) throws`

## UI

### Nutrition day summary card

* If target `isEnabled == true`:

  * show `Remaining Calories = max(0, calorieTarget - totalCalories)`
  * show macro remaining similarly if those targets > 0
* If disabled:

  * show current totals only (no remaining)

### Targets edit UI

Add a sheet: `NutritionTargetsView`

* fields: calories, protein, carbs, fat
* toggle: enable targets
* Save calls `updateTarget(...)`

Entry point:

* Add a small “Target” button/icon in summary card or navigation bar (non-intrusive).

---

# 6.2 Quick Add Calories (no food creation required)

## Purpose

Log calories fast when user doesn’t want to define a food.

## Implementation (non-breaking)

Add a new optional field to `FoodLog` (safe defaults):

* `quickCaloriesKcal: Double?` (nil by default)

Rules:

* If `quickCaloriesKcal != nil`:

  * This log represents calories-only.
  * macros for this log are treated as 0.
  * The UI displays label “Quick Calories” (or “Quick Add”)
  * `food` relationship may be nil OR set to a special internal food

    * Choose ONE approach and be consistent:

      * **Preferred (less model churn): allow `food` to be optional in FoodLog.**

        * If changing relationship optionality is risky in SwiftData for your setup, use the “special food” option below.
      * **Alternative (no relationship change): create a special Food** named “Quick Calories” once and reuse it.

### Safer option (recommended if you don’t want schema churn)

**Special Food approach (no FoodLog relationship changes):**

* On first Quick Add, create/find Food:

  * `name = "Quick Calories"`
  * `gramsPerReference = 1`
  * `kcalPerReference = 1`
  * macros = 0
* For a Quick Add of X kcal:

  * create FoodLog with that Food and set `grams = X`
  * display logic: if `food.name == "Quick Calories"` treat grams as kcal

This keeps FoodLog schema unchanged and avoids SwiftData migration pain.

## UI

In `LogSheet`:

* Add a third mode or a button:

  * Segment: `Food | Meal | Quick Add`
  * Quick Add shows:

    * calories input only
    * category + time + note
* Save creates the quick-add log using the chosen approach.

---

# 6.3 Copy Yesterday (standalone logs only)

## Purpose

Fast repeat of common daily intake.

## Rules (keep simple, avoid messing grouping)

* Copy ONLY FoodLogs where `mealEntry == nil` from previous day.
* Do not copy MealEntries in Phase 6.
* New logs:

  * same food + grams + category + note
  * timestamp:

    * keep the same time-of-day, but on selectedDate
    * if that causes ordering issues, set to noon + incremental minutes

## Service (add-only)

Add:

* `func copyStandaloneLogs(from sourceDate: Date, to targetDate: Date) throws -> Int`
  Returns number of logs created.

## UI

On Nutrition day view:

* Add a small button near the date header or in an overflow menu:

  * “Copy Yesterday”
* Confirmation dialog:

  * “Copy yesterday’s standalone items into today?”

---

# 6.4 Save Meal From Logged MealEntry

## Purpose

Let user turn a logged meal into a reusable template.

## Rules

* Works from a `MealEntry` shown on the day view.
* Creates a new `Meal` template with name:

  * default: existing template name (if available) or “Saved Meal”
  * allow user to edit name before save
* Create `MealItem`s from that entry’s child FoodLogs:

  * keep grams
  * set order based on existing display order

## Service (add-only)

Add:

* `func createMealTemplate(from entry: MealEntry, name: String) throws -> Meal`

## UI

* On MealEntry header: add action “Save as Template”
* Tap opens small prompt to name it then saves
* After saving, optional toast: “Saved”

---

# 6.5 Phase 6 Acceptance Criteria

* No existing Nutrition screens were removed or split; unified Phase 5 Log/Manage flow still works.
* Targets:

  * user can enable/disable
  * remaining calories/macros display correctly
* Quick Add:

  * logs calories with minimal steps
  * totals include quick-add calories
  * no crashes or broken relationships
* Copy Yesterday:

  * copies only standalone logs (no MealEntry duplication)
* Save Meal From Entry:

  * creates a template from a logged MealEntry
  * logging that new template works normally

---

## Notes to the implementer

* Prefer “add-only” changes.
* If any step requires changing SwiftData relationship optionality or migrations that risk breaking existing store, choose the safer alternative (special “Quick Calories” food).
* All new save actions must use the existing error alert pattern; no silent failures.

If you want, tell me whether you’re okay adding an optional `food` relationship on `FoodLog` (migration risk), and I’ll lock the Quick Add spec to the best option for your setup.

---
## Phase 7 — Remove Legacy Nutrition Meal Flow (Non-breaking Cleanup)

This phase is **cleanup only**. It must not change Nutrition data models, persistence behavior, or user-visible features. The goal is to eliminate duplicate/legacy screens and consolidate shared UI logic to reduce redundancy and maintenance risk.

---

# 7.0 Guardrails

1. Do **not** change existing Nutrition models or relationships:

   * `Food`, `FoodLog`, `Meal`, `MealItem`, `MealEntry`, plus any Phase 5 additions.
2. Do **not** change existing service method signatures (you may remove unused legacy wrappers only after all callers are migrated).
3. The unified Phase 5 flow remains the only supported UX:

   * `NutritionDayView` → **LogSheet** (Food/Meal)
   * Menu → **ManageNutritionSheet** (Foods/Meals)
4. No timing-based navigation/dismiss logic may be reintroduced.
5. Prefer deletion over keeping deprecated code—**unless** something is still referenced.

---

# 7.1 Eliminate legacy navigation entry points

## Task

Search the codebase for legacy view usage and remove all routes to them.

### Required search targets

* `NutritionMealsView`
* `NutritionLogMealView`
* `NutritionMealEditorView`
* Any additional “old flow” names related to meals/logging that aren’t used by Phase 5.

### Actions

* If a legacy screen is referenced from navigation, replace the destination with the unified equivalents:

  * Meal template listing/editing → **ManageNutritionSheet**, default tab = Meals
  * Logging a meal → **LogSheet** with mode preset to `.meal`

---

# 7.2 Remove or retire legacy files

## Preferred outcome: delete

If a legacy file is not referenced anywhere after 7.1, delete it:

* `Views/Nutrition/NutritionMealsView.swift`
* `Views/Nutrition/NutritionLogMealView.swift` (if present)
* `Views/Nutrition/NutritionMealEditorView.swift` (if present)

## If a file cannot be deleted immediately

Temporarily convert it into a **thin wrapper**:

* Rename type to `Legacy...` (e.g., `LegacyNutritionMealsView`)
* Add a prominent comment at top: “Deprecated — do not use; scheduled for removal.”
* Implementation must simply present the unified UI:

  * `ManageNutritionSheet` with Meals selected, or
  * the shared meal list/editor subview used by Manage
* No separate logging/editor logic is allowed in legacy wrappers.

---

# 7.3 Consolidate redundant code (minimize duplicate UI logic)

## Goal

There should be exactly one canonical implementation for each concept. Where redundancy exists, extract shared components rather than maintaining parallel logic.

### Canonical concepts (must be single-source)

* Meal template list UI
* Meal template editor UI
* Meal picker UI
* LogSheet UI (food/meal/quick add if present)
* Foods list UI (Manage + Picker reuse patterns)

### Actions

1. Identify duplicate list implementations (same rows/search/filter repeated).
2. Extract shared subviews into small reusable components, for example:

   * `FoodRowView(food: ...)`
   * `MealRowView(meal: ...)`
   * `SearchHeaderView(text: ..., showArchivedToggle: ...)`
3. Extract shared filtering/sorting into helper methods (preferably in `NutritionService` or a small `NutritionQueryHelpers.swift` under `Views/Nutrition/` if it’s UI-specific).
4. Ensure the picker vs manage lists differ only by **behavior** (selection vs edit), not by duplicated data logic.

**Explicit rule:** Do not copy/paste the same filtering logic across views. If you see the same filtering/sorting code twice, consolidate it.

---

# 7.4 Remove legacy service API shims (only after callers migrated)

## Task

After legacy views are removed and all call sites use the new throwing APIs:

* Delete any compatibility methods that exist only to keep old screens compiling, such as:

  * `deleteFood(_:) -> Bool` (if it’s just a wrapper)
  * any “old signature” `logMeal(...)` overloads

Keep only the canonical throwing APIs:

* `archiveFood`, `unarchiveFood`
* `addFoodLog`, `logMeal`
* fetch methods

---

# 7.5 Acceptance Criteria (Phase 7)

* Searching the codebase shows **no references** to:

  * `NutritionMealsView`, `NutritionLogMealView`, `NutritionMealEditorView`
  * (or they exist only as `Legacy*` wrappers and are not reachable from any navigation)
* There is only **one** active UX path for:

  * managing meal templates
  * logging meals
* No duplicate filtering/sorting logic for foods/meals lists exists across multiple files (extracted into shared helpers/subviews).
* Build succeeds.
* Manual smoke test:

  * Create meal template
  * Log it
  * Edit it
  * Delete template (history unaffected)

---

# 7.6 Deliverables

* Deleted or wrapped legacy nutrition meal flow files
* Updated navigation to point exclusively at unified Phase 5 screens
* Extracted shared list row + search header components where redundancy existed
* Removed service shims that are now unused
* Build + smoke test passes

---

## Phase 7.7 — Final Cleanup Pass (No Behavior Changes)

### 1) Reduce redundant code (must-do)

* Scan `Views/Nutrition/` for repeated UI patterns and extract small reusable subviews:

  * `NutritionSectionHeaderView(title: String, totalText: String?)`
  * `FoodLogRowView(log: FoodLog, totals: …)`
  * `MealEntryRowView(entry: MealEntry, childLogs: [FoodLog])`
  * `FoodRowView(food: Food, subtitle: …, trailing: …)`
  * `MealRowView(meal: Meal, subtitle: …)`
* Scan for repeated filtering/sorting code across views and consolidate into:

  * `NutritionService` helpers (preferred for data logic), or
  * `NutritionViewHelpers.swift` (UI-only helpers) under `Views/Nutrition/`

**Rule:** any non-trivial filter/sort should exist in one place only.

### 2) Tighten file organization (nice-to-have)

* Ensure all nutrition views are in `Views/Nutrition/` and named consistently:

  * `NutritionDayView`
  * `NutritionLogSheet`
  * `ManageNutritionSheet`
  * `FoodPickerView`
  * `MealPickerView`
  * `AddFoodView`
  * `MealTemplateEditorView`
  * `NutritionTargetsView` (if Phase 6 exists)
* If `NutritionLogManageViews.swift` is huge, split it into multiple files by feature:

  * `NutritionLogSheet.swift`
  * `ManageNutritionSheet.swift`
  * `FoodPickerView.swift`
  * `MealPickerView.swift`
  * `SharedRows.swift`
    No logic changes, just separation.

### 3) Consistent error handling (must-do)

* Confirm every `try` in views has a `catch` that surfaces an alert (no `try?` unless it’s truly optional).
* Ensure errors use consistent titles/messages (e.g., “Couldn’t Save”, “Couldn’t Archive”)

### 4) Consistent labels + terminology (must-do)

* UI uses “Nutrition” consistently.
* Buttons:

  * Primary: “Log”
  * Manage: “Manage”
  * Foods: “Add Food”
  * Meals: “Add Meal”
  * Archive: “Archive” / “Unarchive”
    No “Log Food / Log Meal” leftover labels.

### 5) Dead code removal

* Remove any unused structs, preview-only wrappers, or unused helper functions left behind after Phase 7.
* Run “Find unused” where possible.

### 6) Final verification

* Build succeeds.
* Manual smoke:

  * Log food
  * Log meal template
  * Archive/unarchive food
  * Show archived toggle works
  * Date navigation still correct

---
## Phase 8 — Drinks (FoodKind + Unit + UI Filters) — Non-breaking

### Goal

Support drinks cleanly without a new Drink model. Drinks are just Foods with a kind + preferred unit (ml). Add UI filtering so places that currently say “Foods” can filter **Foods/Drinks/All** (and rename the section label accordingly).

No mixed-drink logic in Phase 8.

---

# 8.0 Guardrails

1. No new `Drink` model, no new log type. Drinks are still `Food` + `FoodLog`.
2. Don’t change totals math or canonical storage (`FoodLog.grams` stays canonical).
3. New fields must have safe defaults so existing data migrates.
4. Keep Phase 5 unified Log/Manage flows intact.
5. No density conversions. For drinks, **ml is displayed**, but stored as grams (1 ml ≈ 1 g).

---

# 8.1 Data Model additions (FoodKind + Unit)

## Add enums

Create under `Models/Nutrition/`:

* `enum FoodKind: Int, Codable { case food = 0, drink = 1 }`
* `enum FoodUnit: Int, Codable { case grams = 0, milliliters = 1 }`

## Add fields to `Food` (safe defaults)

Add stored raw ints with defaults:

* `kindRaw: Int = 0`  // default Food
* `unitRaw: Int = 0`  // default grams

Add computed properties:

* `var kind: FoodKind { get/set }`
* `var unit: FoodUnit { get/set }`

### Default rules

* Existing rows become `.food` + `.grams`.
* When user sets kind to `.drink`, set unit default to `.milliliters` (but don’t override if user explicitly changed it).

---

# 8.2 Add/Edit Food UI changes

In `AddFoodView` (and edit view if you have one):

1. Add a toggle:

   * Label: “This is a drink”
   * If ON: set `food.kind = .drink`
   * If OFF: set `food.kind = .food`

2. Unit behavior:

   * If kind toggled ON and unit is still default `.grams`, switch to `.milliliters`
   * If toggled OFF and unit is `.milliliters`, switch to `.grams` (optional; acceptable either way)

3. Provide defaults for new drinks (only when fields are empty/zero):

   * `referenceLabel = "1 cup"` (optional)
   * `gramsPerReference = 250`
     (Do not overwrite if user has already entered values.)

---

# 8.3 Logging UI changes (ml display only)

In `LogSheet` food mode:

* If selectedFood.unit == `.milliliters`:

  * show input label as “ml”
  * store the numeric input into `FoodLog.grams` unchanged
* Else show “g”.

In history rows:

* If log.food.unit == `.milliliters`:

  * display amount as “X ml”
* Else “X g”.

No conversion or density logic beyond labeling.

---

# 8.4 Filters (Foods / Drinks / All) across lists

## Add filter enum (UI-only)

* `enum FoodFilterKind { case all, foods, drinks }` (or Int-backed for state)

Default: `.all`

## Where to add filters

### A) Manage Foods list

Near top (beside search / above list):

* Segmented: **All | Foods | Drinks**
* Applies after archive toggle.
* Archive toggle remains separate and default OFF.

### B) FoodPickerView (for logging)

Same segmented filter at top:

* All | Foods | Drinks
* Default All
* Archived toggle stays available, default OFF.

### C) Meal Template Editor (your screenshot)

In the “Foods” section of MealTemplateEditor:

1. Rename the section title from **Foods** to **Items** (or **Ingredients**)
   (This prevents confusion once Drinks exist.)
2. Add filter control above the item list:

   * Segmented: **All | Foods | Drinks**
3. Filter affects which items appear/selectable when choosing a Food for a MealItem.
4. Keep “Show archived” toggle as-is; it composes with the filter.

**Note:** You can keep the underlying model as `MealItem` referencing `Food`—no change required.

---

# 8.5 Service changes (minimal, add-only)

If your view already filters in-memory, service changes are optional.

If you prefer centralized filtering, add add-only fetch helpers:

* `fetchFoods(search: String?, includeArchived: Bool, kind: FoodKind?) -> [Food]`

And for picker sections (favorites/recent/all), ensure kind filter is applied consistently.

---

# 8.6 Acceptance Criteria (Phase 8)

* Existing foods/logs/meals still work without changes.
* User can mark a Food as a drink.
* Drinks default to unit = ml and gramsPerReference defaults to 250 for new drinks (only when unset).
* LogSheet displays ml for drinks and saves to `FoodLog.grams`.
* Manage Foods and FoodPicker have filter: All/Foods/Drinks + archived toggle.
* MealTemplateEditor section is renamed to “Items” (or “Ingredients”) and includes All/Foods/Drinks filter + archived toggle.
* Build succeeds, no crashes, and totals are unchanged.

---

### Implementation note for the agent

Do not add a Drink model or a new logging pipeline. This is purely:

* two new fields on Food,
* UI labeling for ml,
* and list filters.
---

## Phase 9 — Start Real Logging Safely (UserID + Data Integrity + Backup-lite)

### Goal

Make Nutrition safe for daily use on-device without losing logs when you iterate on the app. This phase focuses on:

* re-enabling `userId` filtering safely
* guaranteeing every write sets `userId`
* preventing “invisible data” bugs
* adding a minimal one-way backup export (Nutrition-only) as a safety net

This phase must not refactor existing Nutrition UI flows (LogSheet/Manage) or change core schemas beyond additive safe fields.

---

# 9.0 Guardrails

1. Keep Phase 5 unified flow intact (DayView → LogSheet; Menu → Manage).
2. Do not rename models/properties.
3. Only additive schema changes allowed (new fields with defaults).
4. All write operations must either succeed or show a user-facing error (no silent failures).
5. With `userId` filtering enabled, **no object may be saved with missing/incorrect userId**.

---

# 9.1 Re-enable userId filtering (and make it consistent)

## Task A — Turn filtering back on

* Re-enable `userId == currentUser.id` predicates in all Nutrition fetches:

  * foods list (manage/picker)
  * meal templates list
  * meal entries for day
  * food logs for day
  * recent foods query (based on logs)

## Task B — Audit every write path sets userId

For every creation/upsert, ensure `userId` is always set to `currentUser.id`:

* createFood
* updateFood (must not clear userId)
* addFoodLog
* addQuickCaloriesLog
* createMealTemplate
* addMealItem
* logMeal (MealEntry + FoodLogs)
* any “copy yesterday” or “save meal as template” if present

Add a central helper in `NutritionService`:

* `func requireUserId() throws -> UUID`
  Use it in every write entry point.

If `currentUser` is nil:

* throw `NutritionError.missingUser`
* UI must show an alert (“You must be signed in to log nutrition”)

**No temporary fallback IDs in Phase 9** (since you want userId on).

---

# 9.2 Add integrity checks (prevents phantom/invisible data)

Add lightweight validation functions in `NutritionService`:

### Validate required invariants (throw on failure)

* `Food.userId` exists and equals current userId when writing
* `FoodLog.userId` exists and equals current userId when writing
* `Meal.userId` exists and equals current userId when writing
* `MealEntry.userId` exists and equals current userId when writing
* Relationship integrity:

  * `FoodLog.food.userId` must equal `FoodLog.userId`
  * If `FoodLog.mealEntry != nil`, mealEntry.userId must equal foodLog.userId

Run validation at save time in:

* LogSheet persistSave
* Meal logging function

---

# 9.3 Prevent junk data (strongly recommended before daily logging)

Enforce:

* Food reference grams must be > 0
* FoodLog grams must be > 0 (and quick calories must be > 0)
* MealItem grams must be > 0
* Nutrition values must be >= 0

UI should block Save with a clear error message (alert) rather than silently clamping to 0.

---

# 9.4 Add “Backup Nutrition” (export-only, no DTO system yet)

You don’t want full export/import yet—so do a minimal, safe export-only.

## Output

Create a single JSON file containing:

* foods
* meals
* mealItems
* mealEntries
* foodLogs
* nutritionTargets (optional)

Include:

* `schemaVersion: 1`
* `exportedAt`
* `userId` (currentUser.id)

**Important:** Use a simple Codable export struct (DTOs), but only for Nutrition and only for export. No import.

## Service

Create:

* `Services/NutritionBackupService.swift`

Methods:

* `func exportNutritionJSON() throws -> URL`

  * fetch all Nutrition records for current user
  * map to export DTO structs
  * write file to Documents (or temp) with a timestamp name
  * return file URL

## UI entry point

Add a debug-only (or settings) button:

* “Export Nutrition Backup”
* Presents ShareSheet for the generated JSON file

---

# 9.5 Device logging readiness checklist (Phase 9 acceptance)

* userId filtering is enabled everywhere and works consistently.
* Creating/logging foods/meals never produces records with missing userId.
* If not signed in, logging actions fail with a clear alert (no silent fail).
* No 0-gram logs/items can be saved.
* MealEntry and its FoodLogs always share the same userId.
* Export Nutrition Backup produces a JSON file and ShareSheet opens.
* Build succeeds and basic manual smoke test passes on device:

  * create food, log it
  * create meal template, log it
  * archive/unarchive food
  * export backup

---

# 9B — Nutrition Import (Merge/Upsert, Safety-first)

## Goal

Allow restoring Nutrition data from an exported backup JSON without replacing unrelated app data.

## Scope

* Add import support to `NutritionBackupService`:

  * `func importNutritionJSON(from: URL) throws -> ImportResult`
* Import is **merge/upsert** (by model `id`), not destructive replace.
* Validate:

  * `schemaVersion == 1`
  * backup `userId` matches active `currentUser.id`
  * referenced relationships exist (meal->food, log->food, log->mealEntry)
* Keep user ownership strict:

  * imported nutrition records are assigned/validated to active `userId`
* Save in one transactional flow and return counts.

## UI entry

* Add Settings action:

  * “Import Nutrition Backup”
* Use `fileImporter` for `.json`.
* Show clear success/failure alert.
* On success, refresh `NutritionService` in-memory lists.

## Guardrails

* No full-wipe replace in this phase.
* No import for non-nutrition entities.
* No schema migrations beyond already-supported Phase 9 backup schema.

---

### Notes for the agent

* Keep this phase minimal and safety-focused.
* Do not add import yet.
* Do not refactor view navigation; only add the export button and enforce validation.

---

If it does that pass, your Nutrition codebase will stay maintainable while you add Phase 6 features (targets/quick add/copy yesterday) without it turning into spaghetti.

---

If you run into a case where something still needs “Meals” UI accessible from a button, route it to **Manage → Meals** instead of the legacy screen.

---

If you want me to sanity-check the result after Phase 7, paste the grep results for `NutritionMealsView` and I’ll tell you if anything is still hanging around.

---

If you want one-liner to give the agent:

> “Make `logMeal` throw/optional like other creates, remove/override older checklists, add ‘Show archived’ toggle with unarchive actions in FoodPicker + Manage Foods, block saving if selected food is archived (offer Unarchive), and add MealTemplateEditor empty-state that guides user to create a food first.”

---
## Phase 9C — Exercise Export/Import (npId-first Linking + Skip API Exercises)

Implement an export/import system for all exercise-related models, similar to Nutrition backup, with full import support. **When exporting, do NOT include exercises that came from the API**.

> **Rule:** If an Exercise has `isUserCreated == true` (flag for API-provided items), **exclude it from export**.
> (Only export exercises that are not API-provided.)

### Scope

Include:

* Exercise
* ExerciseSplitDay
* Routine
* Session
* SessionEntry
* SessionSet
* SessionRep (if applicable)

Do not modify existing model structures except where required for safe import.

---

## Phase 9D — Exercise Log Backup That Works Without Exporting Exercises

### Goal

Export and import workout logs (sessions, session entries, sets, reps, routines, split days) **even when exercises are not exported**. During import, exercises must be linked using **npId if present**, otherwise **id**. If an exercise cannot be resolved locally, import still succeeds and the log is preserved in a **pending/unresolved** state (no data loss).

This phase fixes the current issue where logs are being skipped because exercises are excluded.

---

# 9D.0 Guardrails

1. It is OK for `"payload.exercises"` to be empty.
2. Export must never skip `SessionEntry/SessionSet/SessionRep` just because an exercise is excluded.
3. Import must never drop logs; unresolved exercise references must be preserved for later relinking.
4. All new fields must have safe defaults (no migration break).
5. No silent failures: user-visible error on export/import failure.

---

# 9D.1 Data Model Change (minimal, required)

To preserve logs when exercise can’t be resolved, add **one optional string field** to `SessionEntry` (or whatever model holds the exercise reference in your app):

### Add to `SessionEntry`:

* `exerciseNpId: String?` (default nil)  **OR**
* `unresolvedExerciseKey: String?` (default nil)

**Recommended design (best):**
Add both:

* `exerciseNpId: String?` (for stable external linking)
* `unresolvedExerciseId: UUID?` (optional, if you want to store original id too)

If you want the absolute minimum:

* Add `exerciseKey: String?` where you store either npId or UUID string.

This prevents data loss and lets you relink later.

---

# 9D.2 Export Format Updates (DTO changes)

In your export DTOs:

### SessionEntryDTO must include:

* `exerciseId: String?`  (UUID string if you have it)
* `exerciseNpId: String?` (if the exercise has it)

Even if you skip exporting exercises, you still export these keys.

**Do not skip SessionEntryDTO if exerciseNpId is missing.**
Export it anyway with `exerciseId` populated.

### SessionSetDTO / SessionRepDTO remain the same

They reference their parent IDs (`entryId`, `setId`) and should export as long as the parent exists.

---

# 9D.3 Export Rules (the fix)

## A) Keep skipping exercises

You can keep:

* `payload.exercises = []` (or only export user-created, whatever)

## B) Never skip workout logs due to exercise exclusion

Remove the current behavior that does:

* “Skipped session entries due to excluded exercises without npId”
* and the cascading skips for sets/reps.

### New logic:

* Export Sessions
* Export SessionEntries (always, as long as session exists)
* Export SessionSets (always, as long as entry exists)
* Export SessionReps (always, as long as set exists)

The only valid skip reasons are:

* missing parent record (data already corrupted)
* entry has neither `exerciseId` nor `exerciseNpId` (true invalid record)

If you skip, log a warning like:

* “Skipped X entries missing both exerciseId and exerciseNpId.”

---

# 9D.4 Import Rules (npId-first, otherwise id, otherwise unresolved)

When importing a `SessionEntryDTO`:

### Resolve the exercise reference in this order:

1. If `exerciseNpId` present:

   * find existing Exercise with matching npId
   * if found: link normally
2. Else if `exerciseId` present:

   * find existing Exercise with matching id
   * if found: link normally
3. If not found:

   * import the SessionEntry anyway, but mark it unresolved:

     * set `sessionEntry.exercise = nil` **if your relationship allows optional**
     * store `sessionEntry.exerciseNpId = dto.exerciseNpId` and/or `sessionEntry.unresolvedExerciseKey`
     * store `sessionEntry.unresolvedExerciseId = UUID(dto.exerciseId)` if you added it

### Important: if your SessionEntry currently requires `exercise` non-optional

To avoid a breaking relationship change, implement one of these:

**Option 1 (recommended if possible):** make `exercise` optional in SessionEntry
(Additive migration is usually okay; but this can be risky if you already have lots of data.)

**Option 2 (no schema change to relationship):** create a single placeholder Exercise:

* id fixed: a constant UUID
* name: “Unresolved Exercise”
* npId nil
  Then link unresolved entries to this placeholder, and store the real key in `exerciseNpId/unresolvedExerciseKey`.

This keeps the model stable and preserves logs.

---

# 9D.5 Relinking tool (small but important)

Add a service method to fix unresolved entries later:

* `func relinkUnresolvedSessionEntries() throws -> Int`

Behavior:

* For each session entry with unresolved key:

  * try to resolve again using same npId/id rules
  * if resolved: replace placeholder/nil with real exercise and clear unresolved fields

Optional UI:

* In Manage/Debug: “Fix Unresolved Exercises”

Also in UI:

* If an entry is unresolved, show a warning badge and display:

  * “Unknown exercise” or placeholder name
  * (optional) show stored npId/id

---

# 9D.6 Acceptance Criteria

* Export JSON contains:

  * sessions, sessionEntries, sessionSets, sessionReps (not empty when data exists)
  * exercises can be empty
* No warnings about skipping entries because exercises were excluded.
* Import works even if exercises don’t exist on target device:

  * sessions + sets + reps are still imported
  * unresolved entries are preserved (placeholder or nil + stored key)
* If exercises exist (same npId or id), entries link correctly.
* Relink tool successfully converts unresolved entries once exercises become available.

---

# Export Requirements

Create:

`Services/ExerciseBackupService.swift`

### Method:

* `func exportExercisesJSON() throws -> URL`

### Output JSON Structure:

```json
{
  "schemaVersion": 1,
  "exportedAt": "ISO8601",
  "userId": "UUID",
  "payload": {
    "exercises": [],
    "routines": [],
    "splitDays": [],
    "sessions": [],
    "sessionEntries": [],
    "sessionSets": [],
    "sessionReps": []
  }
}
```

### DTO Rules

* Use Codable DTO structs (do NOT make `@Model` types Codable).
* All relationships stored as foreign keys.
* Dates encoded ISO8601.
* IDs exported as String.
* Include `npId` and `isUserCreated` in ExerciseDTO.

### **Export filter rule (critical)**

When exporting exercises:

* **Exclude** exercises where `isUserCreated == true` (API-provided)
* Export only exercises where `isUserCreated == false`

### Relationship handling when excluded exercises exist

If you exclude API exercises, you must ensure exported payload doesn’t contain orphan references:

* When exporting `SessionEntry` / `ExerciseSplitDay` / anything referencing `Exercise`:

  * If the referenced exercise is excluded because `isUserCreated == true`, still export the referencing record **but store the exercise link using `npId` if available**.
  * If no `npId` exists for that excluded exercise, then that referencing record cannot be safely re-linked on import; handle as:

    * Either **skip exporting that referencing record**, OR
    * Export it with `exerciseId = null` and mark it “needs relink”.

**Choose one approach and implement consistently. Recommended:**

* If exercise is excluded AND has no `npId`, skip exporting the dependent record and record it in an `exportWarnings` array.

Add optional:

* `exportWarnings: [String]` at root to list skipped items counts.
---

Phase 10 — Strict Import (npId-first) + Correct Parent Linking (No Model Changes)

Goal

Import workout logs so that:
    •    SessionEntry.exercise links to the correct local Exercise using npId first (then id)
    •    sets/reps import under the right entry/set
    •    import fails if any referenced exercise cannot be resolved
    •    do not edit model relationships / @Relationship annotations

⸻

10.0 Guardrails
    1.    Do not change any SwiftData models (no relationship edits).
    2.    No placeholder exercises, no unresolved fields.
    3.    Import must be transactional: fail early if missing exercises.
    4.    Import must not silently skip entries/sets/reps.
    5.    Exercise resolution is npId-first, then id.

⸻

10.1 Export Requirements (verify/keep)

Your export format is correct if:
    •    SessionEntryDTO includes both:
    •    exerciseNpId: String?
    •    exerciseId: String? (UUID string)
    •    SessionSetDTO includes:
    •    sessionEntryId: String
    •    SessionRepDTO includes:
    •    sessionSetId: String

If split days are included, they must also have exerciseNpId + exerciseId.

No further export changes required.

⸻

10.2 Strict preflight validation (must)

Before creating anything in SwiftData, do a preflight pass:
    1.    Decode JSON.
    2.    Gather all unique exercise references from sessionEntries and splitDays:
    •    prefer exerciseNpId if present
    •    else use exerciseId
    3.    For each reference, attempt to resolve:
    •    if exerciseNpId exists:
    •    fetch Exercise where npId == exerciseNpId
    •    else if exerciseId exists:
    •    fetch Exercise where id == UUID(exerciseId)
    4.    If any are missing:
    •    throw one error listing missing keys (npId and/or id)
    •    abort import (no partial writes)

This ensures import never “half works”.

⸻

10.3 Import algorithm (no relationship edits)

Implement import with explicit object linking by setting parent references at creation time.

Recommended import order
    1.    Routines
    2.    Sessions
    3.    SessionEntries (must resolve exercise first)
    4.    SessionSets (must link to SessionEntry object)
    5.    SessionReps (must link to SessionSet object)
    6.    SplitDays (resolve exercise, link)

Key requirement: build maps by ID

During import, build dictionaries so children link to the correct already-created parent object:
    •    sessionsById: [UUID: Session]
    •    entriesById: [UUID: SessionEntry]
    •    setsById: [UUID: SessionSet]
    •    optionally routinesById

SessionEntries linking (the main fix)

When creating/importing a SessionEntry:
    •    Resolve exercise:
    •    If dto.exerciseNpId exists → query Exercise by npId
    •    Else query by dto.exerciseId
    •    Then init/create entry with:
    •    sessionEntry.exercise = resolvedExercise
    •    sessionEntry.session = parentSession
    •    Store in entriesById[entryId] = entry

This is what makes “open session” show exercises correctly.

Sets linking

For each SessionSetDTO:
    •    find parent entry from entriesById[dto.sessionEntryId]
    •    create set and set:
    •    sessionSet.sessionEntry = parentEntry
    •    store in setsById[setId] = set

Reps linking

For each SessionRepDTO:
    •    find parent set from setsById[dto.sessionSetId]
    •    create rep and set:
    •    rep.sessionSet = parentSet

Do not rely on inferred inverse arrays.
Just setting the parent reference is enough for proper fetches/UI if your UI queries by relationships.

⸻

10.4 Ensure your UI fetch matches the model (common cause of “sets missing”)

If your Session detail screen shows sets/reps by reading arrays like:
    •    entry.sets
    •    set.sessionReps

…and those arrays aren’t automatically populated in your current model style, then during import you may also need to append after creating the child:
    •    after creating SessionSet, do:
    •    parentEntry.sets.append(set) only if sets array exists
    •    after creating SessionRep, do:
    •    parentSet.sessionReps.append(rep) only if array exists

This is NOT a schema change. It’s just making sure the in-memory relationship graph matches what your UI expects.

(If your UI fetches sets via queries instead of arrays, you can skip appending.)

⸻

10.5 Merge vs Replace

Implement both modes:

Replace
    •    delete existing imported data in dependency order (reps → sets → entries → sessions → routines → split days) for this user
    •    then import

Merge
    •    Upsert by id for sessions/routines (and entries/sets/reps if you want)
    •    For MVP, simplest is:
    •    if id exists, skip (or update)
    •    else insert

⸻

10.6 Acceptance Criteria
    •    Import fails with clear error if any referenced exercise cannot be resolved by npId/id.
    •    Successful import: opening a session shows:
    •    entries have correct exercise names (resolved via npId)
    •    sets and reps appear under correct entries/sets
    •    No model files were changed.
    •    No placeholder/unresolved fields remain.
    •    Build succeeds.

⸻

One-liner to give the agent

“Do strict import: preflight resolve all SessionEntry.exercise using exerciseNpId first, else id; fail import if any missing. During import create entries/sets/reps by assigning the correct parent object references (sessionEntry.session, sessionEntry.exercise, sessionSet.sessionEntry, rep.sessionSet). No model relationship changes.”

If you paste the session detail view code that displays sets/reps, I can tell you whether you need the optional .append() step or whether your queries will pick them up automatically.

---

# Import Requirements

### Method:

* `func importExercises(data: Data, mode: ImportMode) throws -> ImportReport`

Where:

* `ImportMode = .merge | .replace`
* `ImportReport` contains inserted/updated/skipped counts per model.

---

# Critical Linking Rule (npId-first)

When importing Exercises:

1. If DTO has `npId`:

   * Try to find existing Exercise with same `npId`.
   * If found → update that record.
2. If not found by `npId`, then:

   * Try to find existing Exercise by `id`.
3. If neither exists:

   * Insert new Exercise.

When importing any record that references an Exercise (SessionEntry, ExerciseSplitDay, etc.):

* Prefer linking by `npId` if present
* Otherwise link by `exerciseId` (UUID string)

---

# Dependency Order for Import

Replace mode:

1. Delete in reverse dependency order:

   * SessionReps
   * SessionSets
   * SessionEntries
   * Sessions
   * ExerciseSplitDays
   * Routines
   * Exercises (only those that are user-created/exported)

2. Insert in forward order:

   * Exercises (exported only)
   * Routines
   * ExerciseSplitDays
   * Sessions
   * SessionEntries
   * SessionSets
   * SessionReps

Merge mode:

* Build lookup dictionaries for existing models.
* Upsert using linking rules.
* Never duplicate if npId matches.

---

# Data Integrity Rules

* SessionEntry.exercise must link using:

  * `exerciseNpId` if present
  * otherwise `exerciseId`
* SplitDay.exercise must use the same rule.
* Validate all foreign keys before commit.
* Perform entire import inside a single SwiftData transaction.
* If validation fails, abort import and throw error.

---

# Safety Requirements

* Do not generate new IDs if DTO provides one.
* Do not overwrite userId.
* All imported records must retain original IDs.
* Validate referential integrity before saving.

---

# Acceptance Criteria

* Export produces valid JSON containing all exercise data **except** exercises where `isUserCreated == true`.
* Export does not produce orphan references; any skipped dependent records are reported via warnings.
* Merge import does not duplicate exercises if npId matches.
* Replace import recreates identical dataset (within the exported subset).
* SessionEntries correctly link to Exercises via npId priority.
* No orphan records after import.
* Build succeeds.

---

If you want, tell me whether your naming is reversed (because “isUserCreated” usually means user-made, but you said it indicates API items). I used your definition exactly: **true = API-provided = exclude**.

---
Yep — you can make that a tiny follow-up phase, but if it already removed them, you can just treat Phase 10B as a verification + cleanup pass.

Phase 10B — Remove Unresolved Tracking (Verification + Cleanup)

Goal

Ensure the codebase has no unresolved/placeholder tracking left, and import behaves strictly:
    •    resolve exercises by npId (then id)
    •    if missing → fail import (no partial import)

Tasks
    1.    Remove leftover model fields (if any)

    •    In SessionEntry delete:
    •    unresolvedExerciseNpId
    •    unresolvedExerciseId
    •    In ExerciseSplitDay delete any unresolved fields if they were added.

    2.    Remove placeholder logic

    •    In ExerciseBackupService delete:
    •    placeholder “Unresolved Exercise” creation/lookup
    •    any branches that assign placeholder
    •    any relink methods (relinkUnresolvedSessionEntries() etc.)

    3.    Remove Settings UI

    •    Delete “Fix Unresolved Exercises” button/action in SettingsView.

    4.    Strict import preflight

    •    Before writing anything:
    •    collect all exerciseNpId (preferred) / exerciseId references from sessionEntries (and splitDays if imported)
    •    verify each resolves to a local Exercise
    •    If any missing:
    •    throw a single error listing missing keys
    •    abort import (no partial changes)

    5.    Ensure linking is npId-first
During import of each SessionEntry:

    •    if exerciseNpId exists → query by Exercise.npId
    •    else → query by Exercise.id

Acceptance
    •    No unresolved fields exist in models.
    •    No placeholder exercise logic exists.
    •    Import fails with a clear error if any exercise cannot be resolved.
    •    A successful import shows exercises + sets/reps correctly.
    •    Build succeeds.

---

## Phase 10B — Remove Unresolved Tracking (Verification + Cleanup)

### Goal

Ensure the codebase has **no unresolved/placeholder tracking** left, and import behaves strictly:

* resolve exercises by `npId` (then `id`)
* if missing → **fail import** (no partial import)

### Tasks

1. **Remove leftover model fields (if any)**

* In `SessionEntry` delete:

  * `unresolvedExerciseNpId`
  * `unresolvedExerciseId`
* In `ExerciseSplitDay` delete any unresolved fields if they were added.

2. **Remove placeholder logic**

* In `ExerciseBackupService` delete:

  * placeholder “Unresolved Exercise” creation/lookup
  * any branches that assign placeholder
  * any relink methods (`relinkUnresolvedSessionEntries()` etc.)

3. **Remove Settings UI**

* Delete “Fix Unresolved Exercises” button/action in `SettingsView`.

4. **Strict import preflight**

* Before writing anything:

  * collect all `exerciseNpId` (preferred) / `exerciseId` references from `sessionEntries` (and splitDays if imported)
  * verify each resolves to a local `Exercise`
* If any missing:

  * throw a single error listing missing keys
  * abort import (no partial changes)

5. **Ensure linking is npId-first**
   During import of each `SessionEntry`:

* if `exerciseNpId` exists → query by `Exercise.npId`
* else → query by `Exercise.id`

### Acceptance

* No unresolved fields exist in models.
* No placeholder exercise logic exists.
* Import fails with a clear error if any exercise cannot be resolved.
* A successful import shows exercises + sets/reps correctly.
* Build succeeds.

---

## Phase 10C — Import Linking Rule: npId-first (id ignored when npId exists)

### Goal

During **exercise backup import**, link `SessionEntry.exercise` (and any other exercise references like `ExerciseSplitDay.exercise`) using this rule:

1. If `exerciseNpId` exists in the payload → **find local Exercise by `npId` and use that**

   * The payload’s `exerciseId` must be ignored in this case (it will not match across devices).
2. Only if `exerciseNpId` is missing/empty → use `exerciseId` to find Exercise by UUID (for user-created/no-npId exercises).

Import must **fail** if an exercise reference cannot be resolved by these rules.

No placeholder exercise, no unresolved tracking.

---

# 10C.0 Guardrails

1. Do not create placeholder/unresolved exercises.
2. Do not store unresolved keys on models.
3. The import must be transactional: if any required exercise cannot be resolved, abort with a clear error listing missing refs.
4. Never use payload `exerciseId` when `exerciseNpId` is present.
5. Keep exporting exercises optional; import assumes exercises already exist locally when referenced by npId.

---

# 10C.1 Update DTO contract (if not already)

Ensure your DTOs include both:

* `exerciseNpId: String?`
* `exerciseId: String?` (UUID string)

For any record that references an exercise:

* `SessionEntryDTO` (required)
* `ExerciseSplitDayDTO` (if importing split days)

---

# 10C.2 Implement a single resolver (centralize the rule)

In `ExerciseBackupService.swift`, create one helper:

### `resolveExercise(exerciseNpId: String?, exerciseId: String?) throws -> Exercise`

Resolution logic (exact):

1. If `exerciseNpId` is non-empty after trimming:

   * fetch local Exercise where `npId == exerciseNpId`
   * if found, return it
   * if not found, throw MissingExercise error **identified by npId**
2. Else:

   * parse `exerciseId` as UUID
   * fetch local Exercise where `id == uuid`
   * if found, return it
   * else throw MissingExercise error **identified by id**

**Important:** Do NOT attempt id lookup if npId was provided (even as fallback). That defeats the rule.

---

# 10C.3 Preflight validation (fail before writing anything)

Before inserting any Sessions/Entries/Sets/Reps:

1. Decode JSON.
2. Collect required exercise references from:

   * all `sessionEntries` (and `splitDays` if applicable)
3. For each reference:

   * If npId present → must resolve by npId
   * Else → must resolve by id
4. If any missing:

   * throw one error listing unique missing references:

     * `npId=...`
     * `id=...`

No database writes should happen if missing refs exist.

---

# 10C.4 Import flow (after preflight passes)

Proceed with your existing object creation order.

### When creating SessionEntry

Use resolver:

* `let exercise = try resolveExercise(dto.exerciseNpId, dto.exerciseId)`
* set `entry.exercise = exercise`

### When importing split days (if applicable)

Same resolver rule:

* `splitDay.exercise = try resolveExercise(dto.exerciseNpId, dto.exerciseId)`

---

# 10C.5 Remove conflicting placeholder/unresolved logic

Delete from import/export code:

* any placeholder exercise creation/lookup
* any `unresolvedExerciseNpId` / `unresolvedExerciseId` usage
* any relink functions (“Fix Unresolved Exercises”)
* any warnings about linking to placeholder

Import should either:

* succeed with correctly linked exercises, or
* fail with “Missing exercise references…”

---

# 10C.6 Acceptance Criteria

* Import succeeds on a device where all referenced `npId`s exist locally.
* If a session entry has `exerciseNpId`, the imported entry links to the local exercise with the same `npId`, regardless of payload UUID.
* Payload UUIDs may differ across devices and do not matter when `npId` exists.
* If `exerciseNpId` is missing, import links by UUID id (for user-created exercises).
* Import fails with a clear list if any referenced exercise cannot be resolved.
* No placeholder/unresolved tracking remains in codebase.
* Build succeeds.

---

### One-line summary for the agent

“Implement strict npId-first resolver: when `exerciseNpId` exists, link by `Exercise.npId` and ignore payload `exerciseId`; only use id when npId is missing. Add preflight validation and remove placeholder/unresolved logic.”

---
## Phase 11 — Nutrition Charts Dashboard Module (Weekly Calories)

### Goal

Add a DashboardModule (like your Weekly Steps) that shows **daily calories over the last 7 days** in both `.medium` and `.large` formats. Pull data from existing Nutrition logs (FoodLogs + MealEntries + quick calories).

No backend required.

---

# 11.0 Guardrails

1. Do not change existing Nutrition schemas.
2. Chart must be derived from existing stored logs (no cached totals tables).
3. Respect `userId` filtering (only current user).
4. Handle missing days as 0 kcal.
5. Keep UI lightweight and consistent with your “Weekly Steps” module.

---

# 11.1 Data: Weekly calories series

### Add to `NutritionService`

Implement:

* `func dailyCaloriesSeries(endingOn endDate: Date, days: Int = 7) throws -> [DailyKcalPoint]`

Where `DailyKcalPoint`:

* `date: Date` (startOfDay)
* `kcal: Double`

#### Calculation rule per day

For each day:

* Fetch all FoodLogs whose `timestamp` is in `[startOfDay, nextDayStart)`
* Compute kcal for each log:

  * If log is “quick calories” → use `quickCaloriesKcal`
  * Else:

    * `kcal = (log.grams / food.gramsPerReference) * food.caloriesPerReference`
* Sum per day.

**Important:** Don’t double-count meal totals. Meals should already be represented as FoodLogs (if your logging expands meals into logs).

#### Performance

Avoid 7 separate fetches if possible:

* Fetch logs for the whole range once (7-day window) and group in memory by day.

---

# 11.2 Chart rendering component

Create:

`Views/Nutrition/NutritionWeeklyCaloriesChart.swift`

Use Swift Charts (iOS 16+):

* Bar chart or line chart (match Weekly Steps style; bars are easiest).
* X-axis: day labels (Mon…Sun or short date)
* Y-axis: kcal

### Tooltip / selection (optional)

* Tap a day to show kcal value.

### Styling

* Follow existing module style:

  * rounded container
  * compact header
  * consistent spacing

---

# 11.3 Dashboard module wiring

Create a new module type:

* `NutritionWeeklyCaloriesModule`

Conforms to your `DashboardModule` protocol.

### `.medium` layout

* Title: “Calories (7d)”
* Chart: compact bars for 7 days
* Footer: “Avg: X” and “Total: Y” (optional)

### `.large` layout

* Same chart but taller + add:

  * “Today: …”
  * “Weekly total”
  * “Weekly average”
  * (Optional) max day highlight

---

# 11.4 Data refresh behavior

The module should update when:

* Day changes
* Nutrition logs change

Implementation options:

* simplest: recompute on `onAppear` and when app becomes active
* better: add a `@Query` for FoodLogs in the 7-day range inside the module view and recompute in-memory when results change

Pick the approach that matches how Weekly Steps module updates.

---

# 11.5 Empty / no data state

If there are no logs in the last 7 days:

* show chart baseline with all zeros
* show text: “No logs yet” (subtle)

---

# 11.6 Acceptance Criteria

* Dashboard shows daily kcal for last 7 days in `.medium` and `.large`.
* Values match Nutrition day totals.
* Missing days show as 0.
* Works with both:

  * individual FoodLog entries
  * meals (as logs)
  * quick calories logs
* Respects current user.
* No schema changes required.
* Build succeeds.

---

### Phase 11.7 (if you want)

Add a segmented toggle in `.large`:

* Calories / Protein / Carbs / Fat
  (using the same daily series function but different macro totals)

If you want, tell me what your Weekly Steps module looks like structurally (file names / protocol), and I’ll match the exact DashboardModule API (init args, sizing enum, etc.).

---

### (Testing) — separate

* Unit-ish tests for date filtering + totals math
* Manual test checklist run (create food, log snack, log meal, edit, archive, copy yesterday, date nav)


---

## Acceptance Criteria (Authoritative)

This replaces all previous acceptance checklists. Only this section defines completion for the Nutrition feature.

### Core Functionality
- Date arrows move between days correctly.
- Calendar button jumps to selected date and refreshes data.
- Logging a Food creates exactly one FoodLog.
- Logging a Meal template creates one MealEntry and its associated FoodLogs.
- Daily totals (calories + macros) update immediately after any change.
- Logs are grouped by category (Breakfast, Lunch, Dinner, Snack, Other).
- MealEntry rows display correctly and expand to show their child FoodLogs.
- Deleting a MealEntry removes its associated FoodLogs.
- Deleting a Meal template does NOT affect historical MealEntries or FoodLogs.

### Unified Log Flow
- Nutrition day view has exactly one primary action: **Log**.
- LogSheet supports switching between Food and Meal modes.
- Food and Meal can both be created inline during logging and auto-selected.
- Save is blocked when validation fails (invalid grams, missing selection, etc.).
- All create/log functions that can fail use `throws` (or optional return) consistently.

### Food Archiving Rules
- Foods are never hard-deleted; they are archived/unarchived only.
- Archived foods are hidden by default in all pickers and lists.
- A `Show archived` toggle reveals archived foods.
- Users can unarchive foods from both Manage and Picker views.
- Attempting to log an archived food blocks save and prompts the user to unarchive first.

### Picker Behavior
- FoodPicker sections appear in this order: Favorites, Recent (last 14 days), All.
- Recent foods are unique and sorted by most recent log date.
- Archived foods are excluded unless `Show archived` is enabled.
- MealPicker allows creating a new template inline and auto-selects it after creation.
- If no foods exist when creating a Meal template, an empty state guides the user to create a Food first.

### Data Integrity
- `grams` is the canonical stored amount for FoodLogs and MealItems.
- Food reference grams must be > 0.
- All nutrition values must be >= 0.
- Save operations do not silently fail.

If all items above pass, Phase 5 is complete.
