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

    static let empty = FoodPickerSections(favorites: [], recent: [], all: [])
}

private struct CoreNutritionDraftValues {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    init(calories: String, protein: String, carbs: String, fat: String) {
        self.calories = Self.parseOptional(calories)
        self.protein = Self.parseOptional(protein)
        self.carbs = Self.parseOptional(carbs)
        self.fat = Self.parseOptional(fat)
    }

    var hasAnyProvidedValue: Bool {
        calories != nil || protein != nil || carbs != nil || fat != nil
    }

    var providedKeys: Set<String> {
        var keys: Set<String> = []
        if calories != nil { keys.insert(NutritionNutrientKey.calories) }
        if protein != nil { keys.insert(NutritionNutrientKey.protein) }
        if carbs != nil { keys.insert(NutritionNutrientKey.carbs) }
        if fat != nil { keys.insert(NutritionNutrientKey.fat) }
        return keys
    }

    private static func parseOptional(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parseOptionalNutritionValue(trimmed)
    }
}

private func parseOptionalNutritionValue(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
        return nil
    }
    return max(0, value)
}

private func parsedExtraNutrients(_ values: [String: String]) -> [String: Double]? {
    let parsed = values.reduce(into: [String: Double]()) { partial, pair in
        let key = NutritionNutrientKey.normalized(pair.key)
        guard !key.isEmpty, let value = parseOptionalNutritionValue(pair.value) else { return }
        partial[key] = value
    }
    return parsed.isEmpty ? nil : parsed
}

private func providedExtraNutrientKeys(_ values: [String: String]) -> Set<String> {
    Set((parsedExtraNutrients(values) ?? [:]).keys)
}

private func binding(for key: String, in values: Binding<[String: String]>) -> Binding<String> {
    let normalizedKey = NutritionNutrientKey.normalized(key)
    return Binding<String>(
        get: { values.wrappedValue[normalizedKey] ?? "" },
        set: { newValue in
            values.wrappedValue[normalizedKey] = newValue
        }
    )
}

struct NutritionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let selectedDate: Date

    @State private var mode: NutritionLogMode = .food
    @State private var selectedFood: FoodItem?
    @State private var selectedMeal: MealRecipe?
    @State private var amount: String = ""
    @State private var foodAmountMode: NutritionLogAmountMode = .baseUnit
    @State private var foodServings: Double = 1
    @State private var mealServings: Double = 1
    @State private var quickCalories: String = ""
    @State private var quickProtein: String = ""
    @State private var quickCarbs: String = ""
    @State private var quickFat: String = ""
    @State private var quickExtraNutrientValues: [String: String] = [:]
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

    private var selectedFoodServingQuantity: Double? {
        guard let selectedFood else { return nil }
        return selectedFood.servingQuantity ?? selectedFood.referenceQuantity
    }

    private var selectedFoodServingLabel: String {
        selectedFood?.servingUnitLabel ?? selectedFood?.referenceLabel ?? "serving"
    }

    private var canSave: Bool {
        switch mode {
        case .food, .drink:
            guard selectedFood != nil else { return false }
            if foodAmountMode == .serving {
                return foodServings > 0
            }
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            return value > 0
        case .meal:
            return selectedMeal != nil && mealServings > 0
        case .quickAdd:
            return quickNutritionValues.hasAnyProvidedValue || quickExtraNutrients != nil
        }
    }

    private var quickNutritionValues: CoreNutritionDraftValues {
        CoreNutritionDraftValues(
            calories: quickCalories,
            protein: quickProtein,
            carbs: quickCarbs,
            fat: quickFat
        )
    }

    private var quickExtraNutrients: [String: Double]? {
        parsedExtraNutrients(quickExtraNutrientValues)
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
                nutritionService.loadNutrientDefinitions()
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
            .onChange(of: selectedFood?.id) {
                foodServings = 1
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

                    if selectedFood != nil {
                        ConnectedCardRow {
                            Picker("Amount", selection: $foodAmountMode) {
                                Text(amountUnitLabel).tag(NutritionLogAmountMode.baseUnit)
                                Text("Servings").tag(NutritionLogAmountMode.serving)
                            }
                            .pickerStyle(.segmented)
                        }

                        ConnectedCardDivider()
                    }

                    if foodAmountMode == .serving, let selectedFood, let servingQuantity = selectedFoodServingQuantity {
                        ConnectedCardRow {
                            LabeledContent("Servings") {
                                TextField("1", value: $foodServings, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        ConnectedCardDivider()

                        ConnectedCardRow {
                            LabeledContent("Serving Size") {
                                Text("\(displayAmount(servingQuantity)) \(selectedFood.unit.shortLabel) per \(selectedFoodServingLabel)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        ConnectedCardRow {
                            LabeledContent("Amount") {
                                TextField(amountUnitLabel, text: $amount)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
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
                        LabeledContent("Servings") {
                            TextField("1", value: $mealServings, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        case .quickAdd:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeaderView(title: "Quick Add")
                NutritionLabelEditorCard(
                    referenceSummary: "entry",
                    calories: $quickCalories,
                    fat: $quickFat,
                    carbs: $quickCarbs,
                    protein: $quickProtein,
                    extraNutrientValues: $quickExtraNutrientValues,
                    definitions: nutritionService.visibleNutrientDefinitions(),
                    profile: quickAddLabelProfile,
                    amountTextOverride: "Total for this entry"
                )
            }
        }
    }

    private var quickAddLabelProfile: NutritionLabelProfile {
        nutritionService.nutritionTarget?.labelProfile ?? .defaultProfile
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
                    LabeledContent("Note") {
                        TextField("Optional", text: $note)
                            .multilineTextAlignment(.trailing)
                    }
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
            let amountValue: Double
            let servingCount: Double?
            if foodAmountMode == .serving, let servingQuantity = selectedFood.servingQuantity ?? Optional(selectedFood.referenceQuantity) {
                amountValue = foodServings * servingQuantity
                servingCount = foodServings
            } else {
                amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                servingCount = nil
            }
            _ = try nutritionService.addFoodLog(
                food: selectedFood,
                grams: amountValue,
                timestamp: timestamp,
                category: category,
                note: trimmedNote,
                amountMode: foodAmountMode,
                servingCount: servingCount
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
            let values = quickNutritionValues
            _ = try nutritionService.addQuickNutritionLog(
                calories: values.calories,
                protein: values.protein,
                carbs: values.carbs,
                fat: values.fat,
                extraNutrients: quickExtraNutrients,
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
    @State private var sections: FoodPickerSections = .empty
    private let initialFilter: FoodFilterKind

    init(initialFilter: FoodFilterKind = .all, onSelect: @escaping (FoodItem) -> Void) {
        self.initialFilter = initialFilter
        self.onSelect = onSelect
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
            refreshSections()
        }
        .onChange(of: searchText) {
            refreshSections()
        }
        .onChange(of: filter) {
            refreshSections()
        }
        .onChange(of: showArchived) {
            refreshSections()
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
                        refreshSections()
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

    private func refreshSections() {
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

        sections = FoodPickerSections(
            favorites: favorites,
            recent: recentWithoutFavorites,
            all: allWithoutFavoritesAndRecent
        )
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
            .screenContentPadding()

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
        CardRowContainer {
            HStack {
                NavigationLink {
                    NutritionFoodDetailView(food: food)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(food.name)
                            if food.isArchived {
                                Text("Archived")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .controlCapsuleSurface()
                            }
                        }

                        if let brand = food.brand {
                            Text(brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    nutritionService.toggleFavorite(food: food)
                } label: {
                    Image(systemName: food.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(food.isFavorite ? .yellow : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button {
                editingFood = food
            } label: {
                Label("Edit", systemImage: "pencil")
            }

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
        NavigationLink {
            NutritionMealDetailView(meal: meal)
        } label: {
            CardRowContainer {
                MealRowView(meal: meal)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingMeal = meal
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                nutritionService.deleteMeal(meal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct NutritionFoodDetailView: View {
    @EnvironmentObject var nutritionService: NutritionService

    let food: FoodItem

    @State private var showEditor = false
    @State private var history: [NutritionLogEntry] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                foodOverviewSection
                foodServingSection
                snapshotHistorySection
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .onAppear(perform: refreshHistory)
        .sheet(isPresented: $showEditor, onDismiss: refreshHistory) {
            NavigationStack {
                NutritionFoodEditorView(food: food) { _ in
                    refreshHistory()
                }
            }
            .presentationDetents([.large])
        }
    }

    private var foodOverviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Nutrition")
            CardRowContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(food.name)
                                .font(.headline)
                            if let brand = food.brand {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(referenceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        NutritionValueTile(title: "Calories", value: displayedCoreValue(NutritionNutrientKey.calories, amount: food.caloriesPerReference, unit: "kcal"))
                        NutritionValueTile(title: "Protein", value: displayedCoreValue(NutritionNutrientKey.protein, amount: food.proteinPerReference, unit: "g"))
                    }

                    HStack(spacing: 10) {
                        NutritionValueTile(title: "Carbs", value: displayedCoreValue(NutritionNutrientKey.carbs, amount: food.carbsPerReference, unit: "g"))
                        NutritionValueTile(title: "Fat", value: displayedCoreValue(NutritionNutrientKey.fat, amount: food.fatPerReference, unit: "g"))
                    }

                    if !foodExtraRows.isEmpty {
                        Divider()
                        VStack(spacing: 8) {
                            ForEach(foodExtraRows, id: \.key) { row in
                                HStack {
                                    Text(row.name)
                                    Spacer()
                                    Text(row.value)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var foodExtraRows: [(key: String, name: String, value: String)] {
        let extras = food.extraNutrients ?? [:]
        return nutritionService.visibleNutrientDefinitions().compactMap { definition in
            let key = NutritionNutrientKey.normalized(definition.key)
            guard food.hasProvidedNutrient(key), let amount = extras[key] else { return nil }
            return (key, definition.displayName, "\(displayAmount(amount)) \(definition.unitLabel)")
        }
    }

    private var foodServingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Serving")
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent("Reference") {
                        Text(referenceDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    LabeledContent("Serving Size") {
                        Text(servingDescription)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var snapshotHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Logged History")

            if history.isEmpty {
                EmptyStateView(
                    title: "No logs yet",
                    systemImage: "clock.arrow.circlepath",
                    message: "Logs for this food will appear here with their saved snapshots."
                )
            } else {
                ConnectedCardSection {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, log in
                        NutritionSnapshotHistoryRow(log: log)
                        if index < history.count - 1 {
                            ConnectedCardDivider(leadingInset: 14)
                        }
                    }
                }
            }
        }
    }

    private var referenceDescription: String {
        "\(displayAmount(food.referenceQuantity)) \(food.unit.shortLabel)"
    }

    private var servingDescription: String {
        guard let quantity = food.servingQuantity, quantity > 0 else {
            return "Not set"
        }
        let label = food.servingUnitLabel ?? "serving"
        return "\(displayAmount(quantity)) \(food.unit.shortLabel) per \(label)"
    }

    private func displayedCoreValue(_ key: String, amount: Double, unit: String) -> String {
        guard food.hasProvidedNutrient(key) else { return "Unknown" }
        if unit == "kcal" {
            return "\(Int(amount.rounded())) kcal"
        }
        return "\(displayAmount(amount)) \(unit)"
    }

    private func refreshHistory() {
        history = nutritionService.snapshotHistory(for: food)
    }
}

private struct NutritionMealDetailView: View {
    @EnvironmentObject var nutritionService: NutritionService

    let meal: MealRecipe

    @State private var showEditor = false
    @State private var history: [NutritionLogEntry] = []

    private var perServing: NutritionFacts {
        nutritionService.calculateRecipePerServingNutrition(meal)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                mealOverviewSection
                mealItemsSection
                mealHistorySection
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(meal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .onAppear(perform: refreshHistory)
        .sheet(isPresented: $showEditor, onDismiss: refreshHistory) {
            NavigationStack {
                NutritionMealTemplateEditorView(meal: meal) { _ in
                    refreshHistory()
                }
            }
            .presentationDetents([.large])
        }
    }

    private var mealOverviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Per Serving")
            CardRowContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(meal.name)
                            .font(.headline)

                        Spacer()

                        Text("\(displayAmount(meal.batchSize)) \(meal.servingUnitLabel ?? "serving")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        NutritionValueTile(title: "Calories", value: "\(Int(perServing.calories.rounded())) kcal")
                        NutritionValueTile(title: "Protein", value: "\(displayAmount(perServing.protein)) g")
                    }

                    HStack(spacing: 10) {
                        NutritionValueTile(title: "Carbs", value: "\(displayAmount(perServing.carbs)) g")
                        NutritionValueTile(title: "Fat", value: "\(displayAmount(perServing.fat)) g")
                    }

                    if !mealExtraRows.isEmpty {
                        Divider()
                        VStack(spacing: 8) {
                            ForEach(mealExtraRows, id: \.key) { row in
                                HStack {
                                    Text(row.name)
                                    Spacer()
                                    Text(row.value)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var mealExtraRows: [(key: String, name: String, value: String)] {
        let extras = perServing.extraNutrients ?? [:]
        return nutritionService.visibleNutrientDefinitions().compactMap { definition in
            let key = NutritionNutrientKey.normalized(definition.key)
            guard let amount = extras[key] else { return nil }
            return (key, definition.displayName, "\(displayAmount(amount)) \(definition.unitLabel)")
        }
    }

    private var mealItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Items")
            ConnectedCardSection {
                ForEach(Array(meal.items.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { index, item in
                    ConnectedCardRow {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.foodItem.name)
                                if let brand = item.foodItem.brand {
                                    Text(brand)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text("\(displayAmount(item.amount)) \(item.foodItem.unit.shortLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if index < meal.items.count - 1 {
                        ConnectedCardDivider(leadingInset: 14)
                    }
                }
            }
        }
    }

    private var mealHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Logged History")

            if history.isEmpty {
                EmptyStateView(
                    title: "No logs yet",
                    systemImage: "clock.arrow.circlepath",
                    message: "Logs for this meal will appear here with their saved snapshots."
                )
            } else {
                ConnectedCardSection {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, log in
                        NutritionSnapshotHistoryRow(log: log)
                        if index < history.count - 1 {
                            ConnectedCardDivider(leadingInset: 14)
                        }
                    }
                }
            }
        }
    }

    private func refreshHistory() {
        history = nutritionService.snapshotHistory(for: meal)
    }
}

private struct NutritionValueTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .controlCardSurface(cornerRadius: 12)
    }
}

private struct NutritionSnapshotHistoryRow: View {
    @EnvironmentObject var nutritionService: NutritionService

    let log: NutritionLogEntry

    var body: some View {
        ConnectedCardRow {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(log.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.subheadline.weight(.semibold))
                    Text(amountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if log.hasProvidedNutrient(NutritionNutrientKey.calories) {
                        Text("\(Int(log.caloriesSnapshot.rounded())) kcal")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(macroDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !extraDescription.isEmpty {
                        Text(extraDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var amountDescription: String {
        if log.amountMode == .serving, let servingCount = log.servingCountSnapshot {
            return "\(displayAmount(servingCount)) \(log.servingUnitLabelSnapshot ?? log.amountUnitSnapshot)"
        }
        if log.amountMode == .quickAdd {
            return "Quick Add"
        }
        return "\(displayAmount(log.amount)) \(log.amountUnitSnapshot)"
    }

    private var macroDescription: String {
        var parts: [String] = []
        if log.hasProvidedNutrient(NutritionNutrientKey.protein) {
            parts.append("P \(displayAmount(log.proteinSnapshot))g")
        }
        if log.hasProvidedNutrient(NutritionNutrientKey.carbs) {
            parts.append("C \(displayAmount(log.carbsSnapshot))g")
        }
        if log.hasProvidedNutrient(NutritionNutrientKey.fat) {
            parts.append("F \(displayAmount(log.fatSnapshot))g")
        }
        return parts.isEmpty ? "Macros unknown" : parts.joined(separator: "  ")
    }

    private var extraDescription: String {
        let extras = log.extraNutrientsSnapshot ?? [:]
        let parts = nutritionService.visibleNutrientDefinitions().compactMap { definition -> String? in
            let key = NutritionNutrientKey.normalized(definition.key)
            guard log.hasProvidedNutrient(key), let value = extras[key] else { return nil }
            return "\(definition.displayName) \(displayAmount(value))\(definition.unitLabel)"
        }
        return parts.joined(separator: "  ")
    }
}

private struct NutritionLabelEditorCard: View {
    let referenceSummary: String
    @Binding var calories: String
    @Binding var fat: String
    @Binding var carbs: String
    @Binding var protein: String
    @Binding var extraNutrientValues: [String: String]
    let definitions: [NutritionNutrientDefinition]
    let profile: NutritionLabelProfile
    var amountTextOverride: String? = nil

    @State private var showsAdditionalNutrients = false

    var body: some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.system(.title2, design: .rounded).weight(.black))
                        .foregroundStyle(.primary)

                    Text(amountTextOverride ?? amountText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                NutritionLabelRule(height: 6)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(energyTitle)
                        .font(.title3.weight(.black))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    NutritionLabelValueField(
                        placeholder: "Optional",
                        text: $calories,
                        unit: "kcal",
                        isProminent: true
                    )
                }
                .padding(.vertical, 9)

                NutritionLabelRule(height: 4)

                NutritionLabelInputRow(
                    title: fatTitle,
                    text: $fat,
                    unit: "g",
                    isStrong: true
                )

                definitionRows(fatChildRows)
                definitionRows(afterFatRows)

                NutritionLabelRule(height: 1)

                NutritionLabelInputRow(
                    title: carbohydrateTitle,
                    text: $carbs,
                    unit: "g",
                    isStrong: true
                )

                definitionRows(carbohydrateChildRows)
                definitionRows(afterCarbohydrateRows)

                NutritionLabelRule(height: 1)

                NutritionLabelInputRow(
                    title: "Protein",
                    text: $protein,
                    unit: "g",
                    isStrong: true
                )

                definitionRows(afterProteinRows)

                if !additionalRows.isEmpty {
                    NutritionLabelRule(height: 4)

                    DisclosureGroup(isExpanded: $showsAdditionalNutrients) {
                        VStack(alignment: .leading, spacing: 0) {
                            definitionRows(additionalRows)
                        }
                    } label: {
                        Text("Additional nutrients")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var titleText: String {
        switch profile {
        case .ukEU:
            return "Nutrition Declaration"
        case .us:
            return "Nutrition Facts"
        case .defaultProfile:
            return "Nutrition Label"
        }
    }

    private var amountText: String {
        switch profile {
        case .ukEU:
            return "Typical values per \(referenceSummary)"
        case .us, .defaultProfile:
            return "Amount per \(referenceSummary)"
        }
    }

    private var energyTitle: String {
        profile == .ukEU ? "Energy" : "Calories"
    }

    private var fatTitle: String {
        profile == .us ? "Total Fat" : "Fat"
    }

    private var carbohydrateTitle: String {
        profile == .us ? "Total Carbohydrate" : "Carbohydrate"
    }

    private var primaryKeys: Set<String> {
        switch profile {
        case .us:
            return ["saturated-fat", "trans-fat", "cholesterol", "sodium", "fiber", "total-sugars", "added-sugars"]
        case .ukEU, .defaultProfile:
            return ["saturated-fat", "total-sugars", "fiber", "salt"]
        }
    }

    private var primaryRows: [NutritionNutrientDefinition] {
        definitions.filter { primaryKeys.contains(normalizedKey($0)) }
    }

    private var fatChildRows: [NutritionNutrientDefinition] {
        let keys: Set<String> = profile == .us ? ["saturated-fat", "trans-fat"] : ["saturated-fat"]
        return rows(matching: keys, in: primaryRows)
    }

    private var afterFatRows: [NutritionNutrientDefinition] {
        let keys: Set<String> = profile == .us ? ["cholesterol", "sodium"] : []
        return rows(matching: keys, in: primaryRows)
    }

    private var carbohydrateChildRows: [NutritionNutrientDefinition] {
        let keys: Set<String> = profile == .us
            ? ["fiber", "total-sugars", "added-sugars"]
            : ["total-sugars"]
        return rows(matching: keys, in: primaryRows)
    }

    private var afterCarbohydrateRows: [NutritionNutrientDefinition] {
        let keys: Set<String> = profile == .us ? [] : ["fiber"]
        return rows(matching: keys, in: primaryRows)
    }

    private var afterProteinRows: [NutritionNutrientDefinition] {
        let keys: Set<String> = profile == .us ? [] : ["salt"]
        return rows(matching: keys, in: primaryRows)
    }

    private var additionalRows: [NutritionNutrientDefinition] {
        definitions.filter { !primaryKeys.contains(normalizedKey($0)) }
    }

    @ViewBuilder
    private func definitionRows(_ rows: [NutritionNutrientDefinition]) -> some View {
        ForEach(rows, id: \.id) { definition in
            let indentLevel = indentLevel(for: definition)
            NutritionLabelRule(height: 1, leadingInset: CGFloat(indentLevel) * 18)
            NutritionLabelInputRow(
                title: displayName(for: definition),
                text: binding(for: definition.key, in: $extraNutrientValues),
                unit: definition.unitLabel,
                indentLevel: indentLevel
            )
        }
    }

    private func rows(
        matching keys: Set<String>,
        in source: [NutritionNutrientDefinition]
    ) -> [NutritionNutrientDefinition] {
        source.filter { keys.contains(normalizedKey($0)) }
    }

    private func normalizedKey(_ definition: NutritionNutrientDefinition) -> String {
        NutritionNutrientKey.normalized(definition.key)
    }

    private func displayName(for definition: NutritionNutrientDefinition) -> String {
        switch normalizedKey(definition) {
        case "saturated-fat":
            return profile == .us ? "Saturated Fat" : "of which saturates"
        case "trans-fat":
            return "Trans Fat"
        case "fiber":
            return profile == .ukEU ? "Fibre" : (profile == .us ? "Dietary Fiber" : "Fiber")
        case "total-sugars":
            return profile == .us ? "Total Sugars" : "of which sugars"
        case "added-sugars":
            return profile == .us ? "Includes Added Sugars" : "of which added sugars"
        default:
            return definition.displayName
        }
    }

    private func indentLevel(for definition: NutritionNutrientDefinition) -> Int {
        switch normalizedKey(definition) {
        case "saturated-fat", "trans-fat", "total-sugars":
            return 1
        case "fiber":
            return profile == .us ? 1 : 0
        case "added-sugars":
            return 2
        default:
            return 0
        }
    }
}

private struct NutritionLabelInputRow: View {
    let title: String
    @Binding var text: String
    let unit: String
    var isStrong = false
    var indentLevel = 0

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(isStrong ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.leading, CGFloat(indentLevel) * 18)

            Spacer(minLength: 8)

            NutritionLabelValueField(
                placeholder: "Optional",
                text: $text,
                unit: unit,
                isProminent: false
            )
        }
        .padding(.vertical, 7)
    }
}

private struct NutritionLabelValueField: View {
    let placeholder: String
    @Binding var text: String
    let unit: String
    let isProminent: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(fieldFont)
                .textFieldStyle(.plain)
                .frame(width: isProminent ? 88 : 74)

            Text(unit)
                .font(unitFont)
                .foregroundStyle(.secondary)
                .frame(minWidth: isProminent ? 30 : 24, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isProminent ? 6 : 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemBackground).opacity(0.72))
        )
    }

    private var fieldFont: Font {
        isProminent ? .title3.weight(.bold) : .subheadline.weight(.semibold)
    }

    private var unitFont: Font {
        isProminent ? .caption.weight(.semibold) : .caption
    }
}

private struct NutritionLabelRule: View {
    let height: CGFloat
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(height > 1 ? 0.82 : 0.22))
            .frame(height: height)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

private func displayAmount(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(Int(value))
    }
    return SetDisplayFormatter.formatDecimal(value)
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
    @State private var gramsPerReference = ""
    @State private var servingQuantity = ""
    @State private var servingUnitLabel = ""
    @State private var labelProfile: NutritionLabelProfile = .defaultProfile
    @State private var usesFoodLabelProfile = false
    @State private var kcalPerReference = ""
    @State private var proteinPerReference = ""
    @State private var carbPerReference = ""
    @State private var fatPerReference = ""
    @State private var extraNutrientValues: [String: String] = [:]
    @State private var kind: FoodItemKind = .food
    @State private var unit: FoodItemUnit = .grams
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                foodDetailsSection
                referenceAmountSection
                servingSection
                nutritionValuesSection

                if let errorText {
                    CardRowContainer {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .screenContentPadding()
        }
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
            nutritionService.loadNutrientDefinitions()
            loadInitialValues()
        }
    }

    private var foodDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Food")
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent("Name") {
                        TextField("Required", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    LabeledContent("Brand") {
                        TextField("Optional", text: $brand)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    Picker("Type", selection: $kind) {
                        Text("Food").tag(FoodItemKind.food)
                        Text("Drink").tag(FoodItemKind.drink)
                        Text("Ingredient").tag(FoodItemKind.ingredient)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    Picker("Unit", selection: $unit) {
                        ForEach(FoodItemUnit.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }
            }
        }
    }

    private var referenceAmountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Reference Amount")
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent("\(unit.displayName) per reference") {
                        TextField("Required", text: $gramsPerReference)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Serving")
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent("\(unit.displayName) per serving") {
                        TextField("Optional", text: $servingQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    LabeledContent("Serving Label") {
                        TextField("Optional", text: $servingUnitLabel)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    Toggle("Food label override", isOn: $usesFoodLabelProfile)
                }

                if usesFoodLabelProfile {
                    ConnectedCardDivider()

                    ConnectedCardRow {
                        Picker("Label Style", selection: $labelProfile) {
                            ForEach(NutritionLabelProfile.allCases) { profile in
                                Text(profile.displayName).tag(profile)
                            }
                        }
                    }
                }
            }
        }
    }

    private var nutritionValuesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Nutrition Per Reference")
            NutritionLabelEditorCard(
                referenceSummary: nutritionReferenceSummary,
                calories: $kcalPerReference,
                fat: $fatPerReference,
                carbs: $carbPerReference,
                protein: $proteinPerReference,
                extraNutrientValues: $extraNutrientValues,
                definitions: nutritionService.visibleNutrientDefinitions(),
                profile: effectiveLabelProfile
            )
        }
    }

    private var effectiveLabelProfile: NutritionLabelProfile {
        usesFoodLabelProfile ? labelProfile : (nutritionService.nutritionTarget?.labelProfile ?? .defaultProfile)
    }

    private var nutritionReferenceSummary: String {
        let amount = Double(gramsPerReference.replacingOccurrences(of: ",", with: "."))

        if let amount, amount > 0 {
            return "\(displayAmount(amount)) \(unit.shortLabel)"
        }

        return "reference"
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
        gramsPerReference = String(format: "%.0f", food.referenceQuantity)
        servingQuantity = food.servingQuantity.map { String(format: "%.0f", $0) } ?? ""
        servingUnitLabel = food.servingUnitLabel ?? food.referenceLabel ?? ""
        usesFoodLabelProfile = food.labelProfile != nil
        labelProfile = food.labelProfile ?? .defaultProfile
        kcalPerReference = food.hasProvidedNutrient(NutritionNutrientKey.calories) ? String(format: "%.0f", food.caloriesPerReference) : ""
        proteinPerReference = food.hasProvidedNutrient(NutritionNutrientKey.protein) ? String(format: "%.0f", food.proteinPerReference) : ""
        carbPerReference = food.hasProvidedNutrient(NutritionNutrientKey.carbs) ? String(format: "%.0f", food.carbsPerReference) : ""
        fatPerReference = food.hasProvidedNutrient(NutritionNutrientKey.fat) ? String(format: "%.0f", food.fatPerReference) : ""
        extraNutrientValues = (food.extraNutrients ?? [:]).reduce(into: [String: String]()) { partial, pair in
            guard food.hasProvidedNutrient(pair.key) else { return }
            partial[NutritionNutrientKey.normalized(pair.key)] = String(format: "%.0f", pair.value)
        }
        kind = food.kind
        unit = food.unit
    }

    private func save() {
        let reference = Double(gramsPerReference.replacingOccurrences(of: ",", with: ".")) ?? 0
        let nutritionValues = CoreNutritionDraftValues(
            calories: kcalPerReference,
            protein: proteinPerReference,
            carbs: carbPerReference,
            fat: fatPerReference
        )
        let kcal = nutritionValues.calories ?? 0
        let protein = nutritionValues.protein ?? 0
        let carbs = nutritionValues.carbs ?? 0
        let fat = nutritionValues.fat ?? 0
        let extraNutrients = parsedExtraNutrients(extraNutrientValues)
        let providedKeys = nutritionValues.providedKeys.union(providedExtraNutrientKeys(extraNutrientValues))
        let servingQuantityValue = Double(servingQuantity.replacingOccurrences(of: ",", with: "."))
        let foodLabelProfile = usesFoodLabelProfile ? labelProfile : nil

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
                referenceLabel: food.referenceLabel,
                gramsPerReference: reference,
                kcalPerReference: kcal,
                proteinPerReference: protein,
                carbPerReference: carbs,
                fatPerReference: fat,
                extraNutrients: extraNutrients,
                providedNutrientKeys: providedKeys,
                servingQuantity: servingQuantityValue,
                servingUnitLabel: servingUnitLabel,
                labelProfile: foodLabelProfile,
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
                referenceLabel: nil,
                gramsPerReference: reference,
                kcalPerReference: kcal,
                proteinPerReference: protein,
                carbPerReference: carbs,
                fatPerReference: fat,
                extraNutrients: extraNutrients,
                providedNutrientKeys: providedKeys,
                servingQuantity: servingQuantityValue,
                servingUnitLabel: servingUnitLabel,
                labelProfile: foodLabelProfile,
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                mealDetailsSection
                mealItemsSection

                if let errorText {
                    CardRowContainer {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle(meal == nil ? "Create Meal Template" : "Edit Meal Template")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
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

    private var mealDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Meal")
            ConnectedCardSection {
                ConnectedCardRow {
                    LabeledContent("Name") {
                        TextField("Required", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    LabeledContent("Batch Size") {
                        TextField("1", text: $batchSizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    LabeledContent("Serving Unit") {
                        TextField("Serving Unit Label", text: $servingUnitLabel)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ConnectedCardDivider()

                ConnectedCardRow {
                    Picker("Default Category", selection: $defaultCategory) {
                        ForEach(FoodLogCategory.displayOrder) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
            }
        }
    }

    private var mealItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: sectionTitle)
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
                    Toggle("Show archived", isOn: $showArchivedFoods)
                }
            }

            if availableFoods.isEmpty {
                EmptyStateView(
                    title: "No \(filter.pluralTitle.lowercased()) yet",
                    systemImage: "fork.knife",
                    message: "Create a \(selectionLabel.lowercased()) first to build this template."
                )

                Button {
                    showCreateFood = true
                } label: {
                    CardRowContainer {
                        Label("Create \(selectionLabel)", systemImage: "plus.circle")
                    }
                }
                .buttonStyle(.plain)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach($draftItems) { $item in
                        mealDraftItemCard($item)
                    }

                    Button {
                        draftItems.append(MealTemplateDraftItem())
                    } label: {
                        CardRowContainer {
                            Label("Add Item", systemImage: "plus.circle")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func mealDraftItemCard(_ item: Binding<MealTemplateDraftItem>) -> some View {
        CardRowContainer {
            VStack(spacing: 10) {
                Button {
                    editingDraftItemID = item.wrappedValue.id
                    showFoodPicker = true
                } label: {
                    HStack {
                        Text(selectionLabel)
                        Spacer()
                        Text(foodName(for: item.wrappedValue.foodId) ?? "Select")
                            .foregroundStyle(item.wrappedValue.foodId == nil ? .secondary : .primary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    LabeledContent("Grams") {
                        TextField("0", text: item.gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if draftItems.count > 1 {
                        Button(role: .destructive) {
                            draftItems.removeAll { $0.id == item.wrappedValue.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
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
