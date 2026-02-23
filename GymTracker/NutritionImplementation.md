
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

If it does that pass, your Nutrition codebase will stay maintainable while you add Phase 6 features (targets/quick add/copy yesterday) without it turning into spaghetti.

---

If you run into a case where something still needs “Meals” UI accessible from a button, route it to **Manage → Meals** instead of the legacy screen.

---

If you want me to sanity-check the result after Phase 7, paste the grep results for `NutritionMealsView` and I’ll tell you if anything is still hanging around.

---

If you want one-liner to give the agent:

> “Make `logMeal` throw/optional like other creates, remove/override older checklists, add ‘Show archived’ toggle with unarchive actions in FoodPicker + Manage Foods, block saving if selected food is archived (offer Unarchive), and add MealTemplateEditor empty-state that guides user to create a food first.”

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
