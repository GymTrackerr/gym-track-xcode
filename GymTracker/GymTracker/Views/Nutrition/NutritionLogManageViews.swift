import SwiftUI

private enum NutritionLogMode: String, CaseIterable, Identifiable {
    case food = "Food"
    case drink = "Drink"
    case meal = "Meal"
    case quickAdd = "Quick Add"

    var id: String { rawValue }
}

enum FoodFilterKind: Int, CaseIterable, Identifiable {
    case all = 0
    case foods = 1
    case drinks = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .foods:
            return "Foods"
        case .drinks:
            return "Drinks"
        }
    }

    var singularTitle: String {
        switch self {
        case .all:
            return "Item"
        case .foods:
            return "Food"
        case .drinks:
            return "Drink"
        }
    }

    var pluralTitle: String {
        switch self {
        case .all:
            return "Items"
        case .foods:
            return "Foods"
        case .drinks:
            return "Drinks"
        }
    }

    var kind: FoodKind? {
        switch self {
        case .all:
            return nil
        case .foods:
            return .food
        case .drinks:
            return .drink
        }
    }
}

private struct FoodPickerSections {
    let favorites: [Food]
    let recent: [Food]
    let all: [Food]
}

struct NutritionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let selectedDate: Date

    @State private var mode: NutritionLogMode = .food
    @State private var selectedFood: Food?
    @State private var selectedMeal: Meal?
    @State private var grams: String = ""
    @State private var quickCalories: String = ""
    @State private var category: FoodLogCategory = .other
    @State private var selectedTime: Date = Date()
    @State private var note: String = ""

    @State private var showFoodPicker = false
    @State private var showMealPicker = false
    @State private var showArchivedFoodAlert = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var amountUnitLabel: String {
        if mode == .drink {
            return selectedFood?.unit.shortLabel ?? FoodUnit.milliliters.shortLabel
        }
        return selectedFood?.unit.shortLabel ?? FoodUnit.grams.shortLabel
    }

    private var canSave: Bool {
        switch mode {
        case .food:
            let gramsValue = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
            return selectedFood != nil && gramsValue > 0
        case .drink:
            let gramsValue = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
            return selectedFood != nil && gramsValue > 0
        case .meal:
            return selectedMeal != nil
        case .quickAdd:
            let calories = Double(quickCalories.replacingOccurrences(of: ",", with: ".")) ?? 0
            return calories > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(NutritionLogMode.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .food:
                    Section("Food") {
                        Button {
                            showFoodPicker = true
                        } label: {
                            HStack {
                                Text("Food")
                                Spacer()
                                Text(selectedFood?.name ?? "Select")
                                    .foregroundStyle(selectedFood == nil ? .secondary : .primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        TextField("Amount (\(amountUnitLabel))", text: $grams)
                            .keyboardType(.decimalPad)
                    }
                case .drink:
                    Section("Drink") {
                        Button {
                            showFoodPicker = true
                        } label: {
                            HStack {
                                Text("Drink")
                                Spacer()
                                Text(selectedFood?.name ?? "Select")
                                    .foregroundStyle(selectedFood == nil ? .secondary : .primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        TextField("Amount (\(amountUnitLabel))", text: $grams)
                            .keyboardType(.decimalPad)
                    }
                case .meal:
                    Section("Meal") {
                        Button {
                            showMealPicker = true
                        } label: {
                            HStack {
                                Text("Template")
                                Spacer()
                                Text(selectedMeal?.name ?? "Select")
                                    .foregroundStyle(selectedMeal == nil ? .secondary : .primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if let selectedMeal {
                            Text("\(selectedMeal.items.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .quickAdd:
                    Section("Quick Add") {
                        TextField("Calories", text: $quickCalories)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(FoodLogCategory.displayOrder) { item in
                            Text(item.displayName).tag(item)
                        }
                    }

                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)

                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                nutritionService.loadFoods()
                nutritionService.loadMeals()
                selectedTime = Date()
                category = nutritionService.defaultCategory(for: Date())
            }
            .navigationDestination(isPresented: $showFoodPicker) {
                NutritionFoodPickerView(initialFilter: mode == .drink ? .drinks : .all) { food in
                    selectedFood = food
                }
            }
            .navigationDestination(isPresented: $showMealPicker) {
                NutritionMealPickerView { meal in
                    selectedMeal = meal
                }
            }
            .onChange(of: selectedMeal?.id) {
                guard mode == .meal, let selectedMeal else { return }
                category = selectedMeal.defaultCategory
            }
            .onChange(of: mode) {
                if mode == .meal, let selectedMeal {
                    category = selectedMeal.defaultCategory
                }
            }
            .alert("Archived Food", isPresented: $showArchivedFoodAlert) {
                Button("Unarchive & Save") {
                    if let selectedFood {
                        do {
                            try nutritionService.unarchiveFood(food: selectedFood)
                            try persistSave()
                        } catch {
                            saveErrorMessage = error.localizedDescription
                            showSaveError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Selected food is archived. Unarchive to log.")
            }
            .alert("Couldn't Save", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        if (mode == .food || mode == .drink), selectedFood?.isArchived == true {
            showArchivedFoodAlert = true
            return
        }
        do {
            try persistSave()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    private func persistSave() throws {
        let currentUserId = try nutritionService.requireUserId()
        let timestamp = nutritionService.dateByPinning(selectedTime, to: selectedDate)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .food:
            guard let selectedFood else {
                throw NutritionService.NutritionError.validation("Select a food before saving.")
            }
            guard selectedFood.userId == currentUserId else {
                throw NutritionService.NutritionError.validation("Selected food does not belong to the active user.")
            }
            let gramsValue = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
            _ = try nutritionService.addFoodLog(
                food: selectedFood,
                grams: gramsValue,
                timestamp: timestamp,
                category: category,
                note: trimmedNote
            )
        case .drink:
            guard let selectedFood else {
                throw NutritionService.NutritionError.validation("Select a drink before saving.")
            }
            guard selectedFood.userId == currentUserId else {
                throw NutritionService.NutritionError.validation("Selected drink does not belong to the active user.")
            }
            let gramsValue = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
            _ = try nutritionService.addFoodLog(
                food: selectedFood,
                grams: gramsValue,
                timestamp: timestamp,
                category: category,
                note: trimmedNote
            )
        case .meal:
            guard let selectedMeal else {
                throw NutritionService.NutritionError.validation("Select a meal template before saving.")
            }
            guard selectedMeal.userId == currentUserId else {
                throw NutritionService.NutritionError.validation("Selected meal template does not belong to the active user.")
            }
            _ = try nutritionService.logMeal(
                template: selectedMeal,
                timestamp: timestamp,
                category: category,
                note: trimmedNote
            )
        case .quickAdd:
            let caloriesValue = Double(quickCalories.replacingOccurrences(of: ",", with: ".")) ?? 0
            _ = try nutritionService.addQuickCaloriesLog(
                calories: caloriesValue,
                timestamp: timestamp,
                category: category,
                note: trimmedNote
            )
        }

        dismiss()
    }
}

struct NutritionFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let onSelect: (Food) -> Void

    @State private var filter: FoodFilterKind = .all
    @State private var searchText: String = ""
    @State private var showArchived: Bool = false
    @State private var showCreateFood = false
    @State private var dismissAfterCreate = false
    @State private var showActionError = false
    @State private var actionErrorMessage = ""
    private let initialFilter: FoodFilterKind

    init(initialFilter: FoodFilterKind = .all, onSelect: @escaping (Food) -> Void) {
        self.initialFilter = initialFilter
        self.onSelect = onSelect
    }

    private var sections: FoodPickerSections {
        let favorites = nutritionService.fetchFavoriteFoods(includeArchived: showArchived, kind: filter.kind)
            .filter(matchesSearch)
        let favoriteIds = Set(favorites.map(\.id))
        let recentWithoutFavorites = nutritionService.fetchRecentFoods(days: 14, includeArchived: showArchived, kind: filter.kind)
            .filter(matchesSearch)
            .filter { food in
                !favoriteIds.contains(food.id)
            }
        let seenIds = favoriteIds.union(recentWithoutFavorites.map(\.id))
        let allWithoutFavoritesAndRecent = nutritionService.fetchFoods(search: searchText, includeArchived: showArchived, kind: filter.kind)
            .filter { food in
                !seenIds.contains(food.id)
            }
        return FoodPickerSections(
            favorites: favorites,
            recent: recentWithoutFavorites,
            all: allWithoutFavoritesAndRecent
        )
    }

    private var pickerTitle: String {
        filter == .drinks ? "Select Drink" : "Select Food"
    }

    private var createTitle: String {
        filter == .drinks ? "New Drink" : "New Food"
    }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $filter) {
                    ForEach(FoodFilterKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show archived", isOn: $showArchived)
            }

            if !sections.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(sections.favorites, id: \.id) { food in
                        foodRow(food)
                    }
                }
            }

            if !sections.recent.isEmpty {
                Section("Recent") {
                    ForEach(sections.recent, id: \.id) { food in
                        foodRow(food)
                    }
                }
            }

            Section("All") {
                ForEach(sections.all, id: \.id) { food in
                    foodRow(food)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle(pickerTitle)
        .onAppear {
            filter = initialFilter
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateFood = true
                } label: {
                    Label(createTitle, systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateFood) {
            NavigationStack {
                NutritionFoodEditorView(preferredKind: filter.kind) { food in
                    onSelect(food)
                    dismissAfterCreate = true
                    showCreateFood = false
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: showCreateFood) {
            if !showCreateFood, dismissAfterCreate {
                dismissAfterCreate = false
                dismiss()
            }
        }
        .alert("Couldn't Complete Action", isPresented: $showActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(actionErrorMessage)
        }
    }

    private func matchesSearch(_ food: Food) -> Bool {
        searchText.isEmpty
            || food.name.localizedCaseInsensitiveContains(searchText)
            || (food.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private func foodRow(_ food: Food) -> some View {
        Button {
            onSelect(food)
            dismiss()
        } label: {
            FoodRowView(food: food) {
                if food.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if food.isArchived {
                Button("Unarchive") {
                    do {
                        try nutritionService.unarchiveFood(food: food)
                    } catch {
                        actionErrorMessage = error.localizedDescription
                        showActionError = true
                    }
                }
                .tint(.green)
            }
        }
    }
}

struct NutritionMealPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let onSelect: (Meal) -> Void

    @State private var searchText: String = ""
    @State private var showCreateMeal = false
    @State private var dismissAfterCreate = false

    private var filteredMeals: [Meal] {
        nutritionService.fetchMeals(search: searchText)
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredMeals, id: \.id) { meal in
                    Button {
                        onSelect(meal)
                        dismiss()
                    } label: {
                        MealRowView(meal: meal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Select Meal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateMeal = true
                } label: {
                    Label("New Meal", systemImage: "plus")
                }
            }
        }
        .onAppear {
            nutritionService.loadMeals()
            nutritionService.loadFoods()
        }
        .sheet(isPresented: $showCreateMeal) {
            NavigationStack {
                NutritionMealTemplateEditorView { meal in
                    onSelect(meal)
                    dismissAfterCreate = true
                    showCreateMeal = false
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: showCreateMeal) {
            if !showCreateMeal, dismissAfterCreate {
                dismissAfterCreate = false
                dismiss()
            }
        }
    }
}

struct ManageNutritionView: View {
    private enum ManageTab: String, CaseIterable, Identifiable {
        case foods = "Foods"
        case meals = "Meals"
        var id: String { rawValue }
    }

    @State private var selectedTab: ManageTab = .foods

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Manage", selection: $selectedTab) {
                    ForEach(ManageTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedTab == .foods {
                    ManageFoodsView()
                } else {
                    ManageMealsView()
                }
            }
            .navigationTitle("Manage")
        }
    }
}

private struct ManageFoodsView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var searchText = ""
    @State private var filter: FoodFilterKind = .all
    @State private var showArchived = false
    @State private var showCreateFood = false
    @State private var editingFood: Food?
    @State private var showEditingFood = false
    @State private var showActionError = false
    @State private var actionErrorMessage = ""

    private var foods: [Food] {
        nutritionService.fetchFoods(search: searchText, includeArchived: showArchived, kind: filter.kind)
    }

    private var createTitle: String {
        "Add \(filter.singularTitle)"
    }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $filter) {
                    ForEach(FoodFilterKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show archived", isOn: $showArchived)
                Button {
                    showCreateFood = true
                } label: {
                    Label(createTitle, systemImage: "plus.circle")
                }
            }

            Section(filter.pluralTitle) {
                ForEach(foods, id: \.id) { food in
                    Button {
                        editingFood = food
                        showEditingFood = true
                    } label: {
                        FoodRowView(food: food) {
                            Button {
                                nutritionService.toggleFavorite(food: food)
                            } label: {
                                Image(systemName: food.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(food.isFavorite ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if food.isArchived {
                            Button("Unarchive") {
                                do {
                                    try nutritionService.unarchiveFood(food: food)
                                } catch {
                                    actionErrorMessage = error.localizedDescription
                                    showActionError = true
                                }
                            }
                            .tint(.green)
                        } else {
                            Button("Archive") {
                                do {
                                    try nutritionService.archiveFood(food: food)
                                } catch {
                                    actionErrorMessage = error.localizedDescription
                                    showActionError = true
                                }
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .sheet(isPresented: $showCreateFood) {
            NavigationStack {
                NutritionFoodEditorView(preferredKind: filter.kind)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showEditingFood) {
            NavigationStack {
                NutritionFoodEditorView(food: editingFood)
            }
            .presentationDetents([.large])
        }
        .alert("Couldn't Complete Action", isPresented: $showActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(actionErrorMessage)
        }
    }
}

private struct ManageMealsView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var searchText = ""
    @State private var showCreateMeal = false
    @State private var editingMeal: Meal?
    @State private var showEditMeal = false

    private var meals: [Meal] {
        nutritionService.fetchMeals(search: searchText)
    }

    var body: some View {
        List {
            Section {
                Button {
                    showCreateMeal = true
                } label: {
                    Label("Add Meal", systemImage: "plus.circle")
                }
            }

            Section("Meals") {
                ForEach(meals, id: \.id) { meal in
                    Button {
                        editingMeal = meal
                        showEditMeal = true
                    } label: {
                        MealRowView(meal: meal)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            nutritionService.deleteMeal(meal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .onAppear {
            nutritionService.loadMeals()
            nutritionService.loadFoods()
        }
        .sheet(isPresented: $showCreateMeal) {
            NavigationStack {
                NutritionMealTemplateEditorView()
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showEditMeal) {
            NavigationStack {
                NutritionMealTemplateEditorView(meal: editingMeal)
            }
            .presentationDetents([.large])
        }
    }
}

struct NutritionFoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let food: Food?
    let preferredKind: FoodKind?
    var onSaved: ((Food) -> Void)?

    init(food: Food? = nil, preferredKind: FoodKind? = nil, onSaved: ((Food) -> Void)? = nil) {
        self.food = food
        self.preferredKind = preferredKind
        self.onSaved = onSaved
    }

    @State private var name = ""
    @State private var brand = ""
    @State private var referenceLabel = ""
    @State private var gramsPerReference = ""
    @State private var kcalPerReference = ""
    @State private var proteinPerReference = ""
    @State private var carbPerReference = ""
    @State private var fatPerReference = ""
    @State private var isDrink = false
    @State private var unit: FoodUnit = .grams
    @State private var errorText: String?

    private var itemTitle: String {
        isDrink ? "Drink" : "Food"
    }

    private var editorTitle: String {
        if food == nil {
            return isDrink ? "Add Drink" : "Add Food"
        }
        return isDrink ? "Edit Drink" : "Edit Food"
    }

    var body: some View {
        Form {
            Section(itemTitle) {
                TextField("Name", text: $name)
                TextField("Brand (optional)", text: $brand)
                TextField("Reference label (optional)", text: $referenceLabel)
                Toggle("This is a drink", isOn: $isDrink)
                    .onChange(of: isDrink) {
                        handleDrinkToggleChanged()
                    }
                Picker("Unit", selection: $unit) {
                    ForEach(FoodUnit.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }

            Section("Reference Amount") {
                TextField("\(unit.displayName) per reference", text: $gramsPerReference)
                    .keyboardType(.decimalPad)
            }

            Section("Nutrition Per Reference") {
                TextField("Calories", text: $kcalPerReference)
                    .keyboardType(.decimalPad)
                TextField("Protein", text: $proteinPerReference)
                    .keyboardType(.decimalPad)
                TextField("Carbs", text: $carbPerReference)
                    .keyboardType(.decimalPad)
                TextField("Fat", text: $fatPerReference)
                    .keyboardType(.decimalPad)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(editorTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
            }
        }
        .onAppear {
            loadInitialValues()
        }
    }

    private func loadInitialValues() {
        guard let food else {
            if preferredKind == .drink {
                isDrink = true
                unit = .milliliters
            }
            return
        }
        name = food.name
        brand = food.brand ?? ""
        referenceLabel = food.referenceLabel ?? ""
        gramsPerReference = String(format: "%.0f", food.gramsPerReference)
        kcalPerReference = String(format: "%.0f", food.kcalPerReference)
        proteinPerReference = String(format: "%.0f", food.proteinPerReference)
        carbPerReference = String(format: "%.0f", food.carbPerReference)
        fatPerReference = String(format: "%.0f", food.fatPerReference)
        isDrink = food.kind == .drink
        unit = food.unit
    }

    private func handleDrinkToggleChanged() {
        if isDrink {
            if unit == .grams {
                unit = .milliliters
            }
        } else if unit == .milliliters {
            unit = .grams
        }
    }

    private func save() {
        let grams = Double(gramsPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let kcal = Double(kcalPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let protein = Double(proteinPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let carb = Double(carbPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let fat = Double(fatPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Name is required."
            return
        }
        guard grams > 0 else {
            errorText = "Grams per reference must be greater than 0."
            return
        }
        guard kcal >= 0, protein >= 0, carb >= 0, fat >= 0 else {
            errorText = "Nutrition values cannot be negative."
            return
        }

        if let food {
            let didSave = nutritionService.updateFood(
                food,
                name: name,
                brand: brand,
                referenceLabel: referenceLabel,
                gramsPerReference: grams,
                kcalPerReference: kcal,
                proteinPerReference: protein,
                carbPerReference: carb,
                fatPerReference: fat,
                kind: isDrink ? .drink : .food,
                unit: unit
            )

            if didSave {
                onSaved?(food)
                dismiss()
            } else {
                errorText = "Could not save this food."
            }
        } else {
            let created = nutritionService.createFood(
                name: name,
                brand: brand,
                referenceLabel: referenceLabel,
                gramsPerReference: grams,
                kcalPerReference: kcal,
                proteinPerReference: protein,
                carbPerReference: carb,
                fatPerReference: fat,
                kind: isDrink ? .drink : .food,
                unit: unit
            )

            if let created {
                onSaved?(created)
                dismiss()
            } else {
                errorText = "Could not create this food."
            }
        }
    }
}

struct MealTemplateDraftItem: Identifiable, Equatable {
    let id: UUID
    var foodId: UUID?
    var gramsText: String

    init(id: UUID = UUID(), foodId: UUID? = nil, gramsText: String = "") {
        self.id = id
        self.foodId = foodId
        self.gramsText = gramsText
    }
}

struct NutritionMealTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let meal: Meal?
    var onSaved: ((Meal) -> Void)? = nil

    @State private var name: String = ""
    @State private var defaultCategory: FoodLogCategory = .other
    @State private var draftItems: [MealTemplateDraftItem] = []
    @State private var filter: FoodFilterKind = .all
    @State private var showArchivedFoods = false
    @State private var showCreateFood = false
    @State private var showFoodPicker = false
    @State private var editingDraftItemID: UUID?
    @State private var errorText: String?
    @State private var didLoadInitialValues = false

    init(
        meal: Meal? = nil,
        onSaved: ((Meal) -> Void)? = nil
    ) {
        self.meal = meal
        self.onSaved = onSaved
    }

    private var availableFoods: [Food] {
        nutritionService.fetchFoods(search: nil, includeArchived: showArchivedFoods, kind: filter.kind)
    }

    private var selectionLabel: String {
        filter.singularTitle
    }

    private var sectionTitle: String {
        filter == .all ? "Items" : filter.pluralTitle
    }

    var body: some View {
        List {
            Section("Meal") {
                TextField("Name", text: $name)
                Picker("Default Category", selection: $defaultCategory) {
                    ForEach(FoodLogCategory.displayOrder) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }

            Section(sectionTitle) {
                Picker("Type", selection: $filter) {
                    ForEach(FoodFilterKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show archived", isOn: $showArchivedFoods)

                if availableFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No \(filter.pluralTitle.lowercased()) yet")
                            .font(.headline)
                        Text("Create a \(selectionLabel.lowercased()) first to build this template.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Create \(selectionLabel)") {
                            showCreateFood = true
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach($draftItems) { $item in
                        VStack(spacing: 8) {
                            Button {
                                editingDraftItemID = item.id
                                showFoodPicker = true
                            } label: {
                                HStack {
                                    Text(selectionLabel)
                                    Spacer()
                                    Text(foodName(for: item.foodId) ?? "Select")
                                        .foregroundStyle(item.foodId == nil ? .secondary : .primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)

                            TextField("Grams", text: $item.gramsText)
                                .keyboardType(.decimalPad)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        draftItems.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        draftItems.move(fromOffsets: source, toOffset: destination)
                    }

                    Button {
                        draftItems.append(MealTemplateDraftItem())
                    } label: {
                        Label("Add Item", systemImage: "plus.circle")
                    }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(meal == nil ? "Create Meal Template" : "Edit Meal Template")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onAppear {
            nutritionService.loadFoods()
            if !didLoadInitialValues {
                loadInitialValues()
                didLoadInitialValues = true
            }
        }
        .sheet(isPresented: $showCreateFood) {
            NavigationStack {
                NutritionFoodEditorView(preferredKind: filter.kind) { _ in
                    nutritionService.loadFoods()
                }
            }
            .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showFoodPicker) {
            NutritionFoodPickerView(initialFilter: filter) { selectedFood in
                guard let id = editingDraftItemID,
                      let index = draftItems.firstIndex(where: { $0.id == id }) else {
                    return
                }
                draftItems[index].foodId = selectedFood.id
                editingDraftItemID = nil
            }
        }
    }

    private func loadInitialValues() {
        guard let meal else {
            if draftItems.isEmpty {
                draftItems = [MealTemplateDraftItem()]
            }
            return
        }

        if name.isEmpty {
            name = meal.name
        }
        defaultCategory = meal.defaultCategory

        if draftItems.isEmpty {
            draftItems = meal.items
                .sorted { $0.order < $1.order }
                .map {
                    MealTemplateDraftItem(
                        id: $0.id,
                        foodId: $0.food.id,
                        gramsText: String(format: "%.0f", $0.grams)
                    )
                }

            if draftItems.isEmpty {
                draftItems = [MealTemplateDraftItem()]
            }
        }
    }

    private func foodName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return nutritionService.foods.first(where: { $0.id == id })?.name
    }

    private func resolvedItems() -> [NutritionService.MealInputItem] {
        draftItems.compactMap { draft in
            guard
                let foodId = draft.foodId,
                let food = nutritionService.foods.first(where: { $0.id == foodId })
            else {
                return nil
            }

            let grams = Double(draft.gramsText.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard grams > 0 else { return nil }

            return NutritionService.MealInputItem(food: food, grams: grams)
        }
    }

    private func save() {
        let items = resolvedItems()

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Meal name is required."
            return
        }

        guard !items.isEmpty else {
            errorText = "Add at least one valid item with grams > 0."
            return
        }

        if let meal {
            if nutritionService.updateMeal(meal, name: name, items: items, defaultCategory: defaultCategory) {
                onSaved?(meal)
                dismiss()
            } else {
                errorText = "Could not update template."
            }
        } else {
            if let createdMeal = nutritionService.createMealTemplate(name: name, items: items, defaultCategory: defaultCategory) {
                onSaved?(createdMeal)
                dismiss()
            } else {
                errorText = "Could not create template."
            }
        }
    }
}
