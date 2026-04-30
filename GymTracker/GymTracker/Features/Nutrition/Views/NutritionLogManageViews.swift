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
    case ingredients = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .foods:
            return "Foods"
        case .drinks:
            return "Drinks"
        case .ingredients:
            return "Ingredients"
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
        case .ingredients:
            return "Ingredient"
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
        case .ingredients:
            return "Ingredients"
        }
    }

    var kind: FoodItemKind? {
        switch self {
        case .all:
            return nil
        case .foods:
            return .food
        case .drinks:
            return .drink
        case .ingredients:
            return .ingredient
        }
    }
}

private struct FoodPickerSections {
    let favorites: [FoodItem]
    let recent: [FoodItem]
    let all: [FoodItem]
}

struct NutritionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let selectedDate: Date

    @State private var mode: NutritionLogMode = .food
    @State private var selectedFood: FoodItem?
    @State private var selectedMeal: MealRecipe?
    @State private var amount: String = ""
    @State private var mealServings: Double = 1
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
        selectedFood?.unit.shortLabel ?? (mode == .drink ? FoodItemUnit.milliliters.shortLabel : FoodItemUnit.grams.shortLabel)
    }

    private var canSave: Bool {
        switch mode {
        case .food, .drink:
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            return selectedFood != nil && value > 0
        case .meal:
            return selectedMeal != nil && mealServings > 0
        case .quickAdd:
            let value = Double(quickCalories.replacingOccurrences(of: ",", with: ".")) ?? 0
            return value > 0
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ConnectedCardSection {
                        ConnectedCardRow {
                            Picker("Mode", selection: $mode) {
                                ForEach(NutritionLogMode.allCases) { value in
                                    Text(value.rawValue).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    modeSection
                    detailsSection
                }
                .screenContentPadding()
            }
            .appBackground()
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                nutritionService.loadFoods()
                nutritionService.loadMeals()
                selectedTime = Date()
                category = nutritionService.defaultCategory(for: Date())
                mealServings = 1
            }
            .navigationDestination(isPresented: $showFoodPicker) {
                NutritionFoodPickerView(initialFilter: mode == .drink ? .drinks : .foods) { food in
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

    @ViewBuilder
    private var modeSection: some View {
        switch mode {
        case .food, .drink:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeaderView(title: mode == .drink ? "Drink" : "Food")
                ConnectedCardSection {
                    Button {
                        showFoodPicker = true
                    } label: {
                        ConnectedCardRow {
                            pickerRow(
                                title: mode == .drink ? "Drink" : "Food",
                                value: selectedFood?.name ?? "Select"
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    ConnectedCardDivider()

                    ConnectedCardRow {
                        TextField("Amount (\(amountUnitLabel))", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                }
            }
        case .meal:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeaderView(title: "Meal")
                ConnectedCardSection {
                    Button {
                        showMealPicker = true
                    } label: {
                        ConnectedCardRow {
                            pickerRow(title: "Template", value: selectedMeal?.name ?? "Select")
                        }
                    }
                    .buttonStyle(.plain)

                    if let selectedMeal {
                        ConnectedCardDivider()
                        ConnectedCardRow {
                            Text("\(selectedMeal.items.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ConnectedCardDivider()

                    ConnectedCardRow {
                        TextField("Servings", value: $mealServings, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }
            }
        case .quickAdd:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeaderView(title: "Quick Add")
                ConnectedCardSection {
                    ConnectedCardRow {
                        TextField("Calories", text: $quickCalories)
                            .keyboardType(.decimalPad)
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Details")
            ConnectedCardSection {
                ConnectedCardRow {
                    Picker("Category", selection: $category) {
                        ForEach(FoodLogCategory.displayOrder) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    TextField("Note (optional)", text: $note)
                }
            }
        }
    }

    private func pickerRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(value == "Select" ? .secondary : .primary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
        case .food, .drink:
            guard let selectedFood else {
                throw NutritionService.NutritionError.validation("Select a food before saving.")
            }
            guard selectedFood.userId == currentUserId else {
                throw NutritionService.NutritionError.validation("Selected food does not belong to the active user.")
            }
            let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            _ = try nutritionService.addFoodLog(
                food: selectedFood,
                grams: amountValue,
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
                amount: mealServings,
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

    let onSelect: (FoodItem) -> Void

    @State private var filter: FoodFilterKind = .all
    @State private var searchText: String = ""
    @State private var showArchived: Bool = false
    @State private var showCreateFood = false
    @State private var dismissAfterCreate = false
    @State private var showActionError = false
    @State private var actionErrorMessage = ""
    private let initialFilter: FoodFilterKind

    init(initialFilter: FoodFilterKind = .all, onSelect: @escaping (FoodItem) -> Void) {
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
        return FoodPickerSections(favorites: favorites, recent: recentWithoutFavorites, all: allWithoutFavoritesAndRecent)
    }

    private var pickerTitle: String {
        filter == .drinks ? "Select Drink" : "Select Food"
    }

    private var createTitle: String {
        filter == .drinks ? "New Drink" : "New Food"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                foodFilterCard

                if !sections.favorites.isEmpty {
                    foodSection(title: "Favorites", foods: sections.favorites)
                }

                if !sections.recent.isEmpty {
                    foodSection(title: "Recent", foods: sections.recent)
                }

                foodSection(title: "All", foods: sections.all)
            }
            .screenContentPadding()
        }
        .appBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always)
        )
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

    private func matchesSearch(_ food: FoodItem) -> Bool {
        searchText.isEmpty
            || food.name.localizedCaseInsensitiveContains(searchText)
            || (food.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private var foodFilterCard: some View {
        ConnectedCardSection {
            ConnectedCardRow {
                Picker("Type", selection: $filter) {
                    ForEach(FoodFilterKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            ConnectedCardDivider()

            ConnectedCardRow {
                Toggle("Show archived", isOn: $showArchived)
            }
        }
    }

    private func foodSection(title: String, foods: [FoodItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: title)

            if foods.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "No \(title.lowercased())" : "No results",
                    systemImage: "fork.knife",
                    message: searchText.isEmpty ? "Create an item to see it here." : "No items match your search."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(foods, id: \.id) { food in
                        selectableFoodCard(food)
                    }
                }
            }
        }
    }

    private func selectableFoodCard(_ food: FoodItem) -> some View {
        Button {
            onSelect(food)
            dismiss()
        } label: {
            CardRowContainer {
                FoodRowView(food: food) {
                    if food.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if food.isArchived {
                Button {
                    do {
                        try nutritionService.unarchiveFood(food: food)
                    } catch {
                        actionErrorMessage = error.localizedDescription
                        showActionError = true
                    }
                } label: {
                    Label("Unarchive", systemImage: "archivebox")
                }
            }
        }
    }
}

struct NutritionMealPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let onSelect: (MealRecipe) -> Void

    @State private var searchText: String = ""
    @State private var showCreateMeal = false
    @State private var dismissAfterCreate = false

    private var filteredMeals: [MealRecipe] {
        nutritionService.fetchMeals(search: searchText)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                mealPickerSection
            }
            .screenContentPadding()
        }
        .appBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always)
        )
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

    private var mealPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Meals")

            if filteredMeals.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "No meals" : "No results",
                    systemImage: "fork.knife",
                    message: searchText.isEmpty ? "Create a meal template to see it here." : "No meals match your search."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredMeals, id: \.id) { meal in
                        selectableMealCard(meal)
                    }
                }
            }
        }
    }

    private func selectableMealCard(_ meal: MealRecipe) -> some View {
        Button {
            onSelect(meal)
            dismiss()
        } label: {
            CardRowContainer {
                MealRowView(meal: meal)
            }
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 0) {
                ConnectedCardSection {
                    ConnectedCardRow {
                        Picker("Manage", selection: $selectedTab) {
                            ForEach(ManageTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if selectedTab == .foods {
                    ManageFoodsView()
                } else {
                    ManageMealsView()
                }
            }
            .navigationTitle("Manage")
            .appBackground()
        }
    }
}

private struct ManageFoodsView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var searchText = ""
    @State private var filter: FoodFilterKind = .all
    @State private var showArchived = false
    @State private var showCreateFood = false
    @State private var editingFood: FoodItem?
    @State private var showActionError = false
    @State private var actionErrorMessage = ""

    private var foods: [FoodItem] {
        nutritionService.fetchFoods(search: searchText, includeArchived: showArchived, kind: filter.kind)
    }

    private var createTitle: String {
        "Add \(filter.singularTitle)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                manageFoodControls
                managedFoodSection
            }
            .screenContentPadding()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always)
        )
        .sheet(isPresented: $showCreateFood) {
            NavigationStack {
                NutritionFoodEditorView(preferredKind: filter.kind)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingFood) { food in
            NavigationStack {
                NutritionFoodEditorView(food: food)
            }
            .presentationDetents([.large])
        }
        .alert("Couldn't Complete Action", isPresented: $showActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(actionErrorMessage)
        }
    }

    private var manageFoodControls: some View {
        ConnectedCardSection {
            ConnectedCardRow {
                Picker("Type", selection: $filter) {
                    ForEach(FoodFilterKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            ConnectedCardDivider()

            ConnectedCardRow {
                Toggle("Show archived", isOn: $showArchived)
            }

            ConnectedCardDivider()

            Button {
                showCreateFood = true
            } label: {
                ConnectedCardRow {
                    Label(createTitle, systemImage: "plus.circle")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var managedFoodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: filter.pluralTitle)

            if foods.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "No \(filter.pluralTitle.lowercased())" : "No results",
                    systemImage: "fork.knife",
                    message: searchText.isEmpty ? "Add an item to see it here." : "No items match your search."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(foods, id: \.id) { food in
                        managedFoodCard(food)
                    }
                }
            }
        }
    }

    private func managedFoodCard(_ food: FoodItem) -> some View {
        Button {
            editingFood = food
        } label: {
            CardRowContainer {
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            if food.isArchived {
                Button {
                    do {
                        try nutritionService.unarchiveFood(food: food)
                    } catch {
                        actionErrorMessage = error.localizedDescription
                        showActionError = true
                    }
                } label: {
                    Label("Unarchive", systemImage: "archivebox")
                }
            } else {
                Button {
                    do {
                        try nutritionService.archiveFood(food: food)
                    } catch {
                        actionErrorMessage = error.localizedDescription
                        showActionError = true
                    }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
    }
}

private struct ManageMealsView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var searchText = ""
    @State private var showCreateMeal = false
    @State private var editingMeal: MealRecipe?

    private var meals: [MealRecipe] {
        nutritionService.fetchMeals(search: searchText)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                manageMealControls
                managedMealSection
            }
            .screenContentPadding()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always)
        )
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
        .sheet(item: $editingMeal) { meal in
            NavigationStack {
                NutritionMealTemplateEditorView(meal: meal)
            }
            .presentationDetents([.large])
        }
    }

    private var manageMealControls: some View {
        ConnectedCardSection {
            Button {
                showCreateMeal = true
            } label: {
                ConnectedCardRow {
                    Label("Add Meal", systemImage: "plus.circle")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var managedMealSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Meals")

            if meals.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "No meals" : "No results",
                    systemImage: "fork.knife",
                    message: searchText.isEmpty ? "Add a meal to see it here." : "No meals match your search."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(meals, id: \.id) { meal in
                        managedMealCard(meal)
                    }
                }
            }
        }
    }

    private func managedMealCard(_ meal: MealRecipe) -> some View {
        Button {
            editingMeal = meal
        } label: {
            CardRowContainer {
                MealRowView(meal: meal)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                nutritionService.deleteMeal(meal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct NutritionFoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let food: FoodItem?
    let preferredKind: FoodItemKind?
    var onSaved: ((FoodItem) -> Void)?

    init(food: FoodItem? = nil, preferredKind: FoodItemKind? = nil, onSaved: ((FoodItem) -> Void)? = nil) {
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
    @State private var kind: FoodItemKind = .food
    @State private var unit: FoodItemUnit = .grams
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Food") {
                LabeledContent("Name") {
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Brand") {
                    TextField("Optional", text: $brand)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Reference Label") {
                    TextField("Optional", text: $referenceLabel)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Type", selection: $kind) {
                    Text("Food").tag(FoodItemKind.food)
                    Text("Drink").tag(FoodItemKind.drink)
                    Text("Ingredient").tag(FoodItemKind.ingredient)
                }
                Picker("Unit", selection: $unit) {
                    ForEach(FoodItemUnit.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }

            Section("Reference Amount") {
                LabeledContent("\(unit.displayName) per reference") {
                    TextField("Required", text: $gramsPerReference)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Nutrition Per Reference") {
                LabeledContent("Calories") {
                    TextField("0", text: $kcalPerReference)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Protein") {
                    TextField("0", text: $proteinPerReference)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Carbs") {
                    TextField("0", text: $carbPerReference)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Fat") {
                    TextField("0", text: $fatPerReference)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
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
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(food == nil ? "Add Food" : "Edit Food")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            loadInitialValues()
        }
    }

    private func loadInitialValues() {
        guard let food else {
            if let preferredKind {
                kind = preferredKind
                if preferredKind == .drink {
                    unit = .milliliters
                }
            }
            return
        }

        name = food.name
        brand = food.brand ?? ""
        referenceLabel = food.referenceLabel ?? ""
        gramsPerReference = String(format: "%.0f", food.referenceQuantity)
        kcalPerReference = String(format: "%.0f", food.caloriesPerReference)
        proteinPerReference = String(format: "%.0f", food.proteinPerReference)
        carbPerReference = String(format: "%.0f", food.carbsPerReference)
        fatPerReference = String(format: "%.0f", food.fatPerReference)
        kind = food.kind
        unit = food.unit
    }

    private func save() {
        let reference = Double(gramsPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let kcal = Double(kcalPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let protein = Double(proteinPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let carbs = Double(carbPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let fat = Double(fatPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Name is required."
            return
        }
        guard reference > 0 else {
            errorText = "Reference amount must be greater than 0."
            return
        }
        guard kcal >= 0, protein >= 0, carbs >= 0, fat >= 0 else {
            errorText = "Nutrition values cannot be negative."
            return
        }

        if let food {
            let didSave = nutritionService.updateFood(
                food,
                name: name,
                brand: brand,
                referenceLabel: referenceLabel,
                gramsPerReference: reference,
                kcalPerReference: kcal,
                proteinPerReference: protein,
                carbPerReference: carbs,
                fatPerReference: fat,
                kind: kind,
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
                gramsPerReference: reference,
                kcalPerReference: kcal,
                proteinPerReference: protein,
                carbPerReference: carbs,
                fatPerReference: fat,
                kind: kind,
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

    let meal: MealRecipe?
    var onSaved: ((MealRecipe) -> Void)? = nil

    @State private var name: String = ""
    @State private var defaultCategory: FoodLogCategory = .other
    @State private var batchSizeText: String = "1"
    @State private var servingUnitLabel: String = "serving"
    @State private var draftItems: [MealTemplateDraftItem] = []
    @State private var filter: FoodFilterKind = .all
    @State private var showArchivedFoods = false
    @State private var showCreateFood = false
    @State private var showFoodPicker = false
    @State private var editingDraftItemID: UUID?
    @State private var errorText: String?
    @State private var didLoadInitialValues = false

    init(meal: MealRecipe? = nil, onSaved: ((MealRecipe) -> Void)? = nil) {
        self.meal = meal
        self.onSaved = onSaved
    }

    private var availableFoods: [FoodItem] {
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
                LabeledContent("Name") {
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Batch Size") {
                    TextField("1", text: $batchSizeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Serving Unit") {
                    TextField("Serving Unit Label", text: $servingUnitLabel)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Default Category", selection: $defaultCategory) {
                    ForEach(FoodLogCategory.displayOrder) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }
            .cardListRowStyle()

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

                            LabeledContent("Grams") {
                                TextField("0", text: $item.gramsText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.vertical, 4)
                        .cardListRowStyle()
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
                    .cardListRowStyle()
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .cardListRowStyle()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(meal == nil ? "Create Meal Template" : "Edit Meal Template")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
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
        batchSizeText = String(format: "%.2f", meal.batchSize)
        servingUnitLabel = meal.servingUnitLabel ?? "serving"

        if draftItems.isEmpty {
            draftItems = meal.items
                .sorted { $0.order < $1.order }
                .map {
                    MealTemplateDraftItem(
                        id: $0.id,
                        foodId: $0.foodItem.id,
                        gramsText: String(format: "%.0f", $0.amount)
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
        let batchSize = Double(batchSizeText.replacingOccurrences(of: ",", with: ".")) ?? 0

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Meal name is required."
            return
        }
        guard batchSize > 0 else {
            errorText = "Batch size must be greater than 0."
            return
        }
        guard !servingUnitLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Serving unit label is required."
            return
        }

        guard !items.isEmpty else {
            errorText = "Add at least one valid item with grams > 0."
            return
        }

        if let meal {
            if nutritionService.updateMeal(
                meal,
                name: name,
                items: items,
                defaultCategory: defaultCategory,
                batchSize: batchSize,
                servingUnitLabel: servingUnitLabel
            ) {
                onSaved?(meal)
                dismiss()
            } else {
                errorText = "Could not update template."
            }
        } else {
            if let createdMeal = nutritionService.createMealTemplate(
                name: name,
                items: items,
                defaultCategory: defaultCategory,
                batchSize: batchSize,
                servingUnitLabel: servingUnitLabel
            ) {
                onSaved?(createdMeal)
                dismiss()
            } else {
                errorText = "Could not create template."
            }
        }
    }
}
