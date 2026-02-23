
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

## Phase 7 — Remove legacy Nutrition meal flow (single source of truth)

### Goal

There must be **one** way to manage meal templates and **one** way to log meals: the unified Phase 5 flow (`ManageNutritionSheet` + `LogSheet`).

### Tasks

1. **Find and remove all navigation to legacy views**

* Search entire project for:

  * `NutritionMealsView`
  * `NutritionLogMealView`
  * `NutritionMealEditorView`
* For every reference:

  * Replace with unified equivalents (Manage sheet → Meals tab; LogSheet in Meal mode)
  * If it’s not referenced anywhere (dead code), remove it.

2. **Delete or explicitly deprecate legacy files**
   Do one of these:

**Preferred:** delete these files if no longer used:

* `Views/Nutrition/NutritionMealsView.swift`
* any legacy log-meal/editor files

**If deletion causes routing pain:** keep temporarily but make them wrappers:

* Rename to `LegacyNutritionMealsView`
* Add “DEPRECATED” comment
* Internally they should only present the unified Manage Meals UI (no separate list/editor/log logic)

3. **Remove legacy service API shims**

* After updating callers, remove any “legacy compatibility” methods you added (example: `deleteFood(_:)` that returns Bool).
* Keep only the `throws` APIs:

  * `archiveFood`, `unarchiveFood`
  * `addFoodLog`, `logMeal`
  * fetch functions

4. **Ensure there is exactly one implementation of each core UI**
   There should be only one of each (no duplicates with different names):

* Meal template list UI
* Meal template editor UI
* Meal picker UI
* LogSheet

If you need reuse, extract shared subviews instead of parallel screens.

### Acceptance (Phase 7)

* No remaining references to legacy view types in the codebase (search returns none), OR they exist only as `Legacy*` wrappers and are not reachable from UI.
* Build succeeds.
* Manual smoke:

  * Create meal template
  * Log meal
  * Edit template
  * Delete template (history unaffected)

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
