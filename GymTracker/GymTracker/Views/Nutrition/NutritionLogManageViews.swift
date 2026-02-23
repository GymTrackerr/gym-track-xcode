import SwiftUI

private enum NutritionLogMode: String, CaseIterable, Identifiable {
    case food = "Food"
    case meal = "Meal"

    var id: String { rawValue }
}

struct NutritionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let selectedDate: Date

    @AppStorage("nutrition.lastCategoryRaw") private var lastCategoryRaw: Int = FoodLogCategory.other.rawValue

    @State private var mode: NutritionLogMode = .food
    @State private var selectedFood: Food?
    @State private var selectedMeal: Meal?
    @State private var grams: String = ""
    @State private var category: FoodLogCategory = .other
    @State private var selectedTime: Date = Date()
    @State private var note: String = ""

    @State private var showFoodPicker = false
    @State private var showMealPicker = false
    @State private var showArchivedFoodAlert = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var canSave: Bool {
        switch mode {
        case .food:
            let gramsValue = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
            return selectedFood != nil && gramsValue > 0
        case .meal:
            return selectedMeal != nil
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

                        TextField("Grams", text: $grams)
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
                category = FoodLogCategory(rawValue: lastCategoryRaw) ?? nutritionService.defaultCategory(for: Date())
            }
            .navigationDestination(isPresented: $showFoodPicker) {
                NutritionFoodPickerView { food in
                    selectedFood = food
                }
            }
            .navigationDestination(isPresented: $showMealPicker) {
                NutritionMealPickerView { meal in
                    selectedMeal = meal
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
        if mode == .food, selectedFood?.isArchived == true {
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
        let timestamp = nutritionService.dateByPinning(selectedTime, to: selectedDate)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .food:
            guard let selectedFood else {
                throw NutritionService.NutritionError.validation("Select a food before saving.")
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
            _ = try nutritionService.logMeal(
                template: selectedMeal,
                timestamp: timestamp,
                category: category,
                note: trimmedNote
            )
        }

        lastCategoryRaw = category.rawValue
        dismiss()
    }
}

struct NutritionFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let onSelect: (Food) -> Void

    @State private var searchText: String = ""
    @State private var showArchived: Bool = false
    @State private var showCreateFood = false
    @State private var dismissAfterCreate = false
    @State private var showActionError = false
    @State private var actionErrorMessage = ""

    private var favorites: [Food] {
        nutritionService.fetchFavoriteFoods(includeArchived: showArchived)
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false) }
    }

    private var recent: [Food] {
        nutritionService.fetchRecentFoods(days: 14, includeArchived: showArchived)
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false) }
    }

    private var allFoods: [Food] {
        nutritionService.fetchFoods(search: searchText, includeArchived: showArchived)
    }

    private var recentWithoutFavorites: [Food] {
        let favoriteIds = Set(favorites.map(\.id))
        return recent.filter { !favoriteIds.contains($0.id) }
    }

    private var allWithoutFavoritesAndRecent: [Food] {
        let seenIds = Set(favorites.map(\.id)).union(recentWithoutFavorites.map(\.id))
        return allFoods.filter { !seenIds.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                Toggle("Show archived", isOn: $showArchived)
            }

            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites, id: \.id) { food in
                        foodRow(food)
                    }
                }
            }

            if !recentWithoutFavorites.isEmpty {
                Section("Recent") {
                    ForEach(recentWithoutFavorites, id: \.id) { food in
                        foodRow(food)
                    }
                }
            }

            Section("All") {
                ForEach(allWithoutFavoritesAndRecent, id: \.id) { food in
                    foodRow(food)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Select Food")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateFood = true
                } label: {
                    Label("New Food", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateFood) {
            NavigationStack {
                NutritionFoodEditorView { food in
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

    private func foodRow(_ food: Food) -> some View {
        Button {
            onSelect(food)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(food.name)
                            .foregroundStyle(.primary)
                        if food.isArchived {
                            Text("Archived")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let brand = food.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

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
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nutritionService.meals.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return nutritionService.meals.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredMeals, id: \.id) { meal in
                    Button {
                        onSelect(meal)
                        dismiss()
                    } label: {
                        HStack {
                            Text(meal.name)
                            Spacer()
                            Text("\(meal.items.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                    Label("New Meal Template", systemImage: "plus")
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

struct ManageNutritionSheet: View {
    @Environment(\.dismiss) private var dismiss

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ManageFoodsView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showCreateFood = false
    @State private var editingFood: Food?
    @State private var showEditingFood = false
    @State private var showActionError = false
    @State private var actionErrorMessage = ""

    private var foods: [Food] {
        nutritionService.fetchFoods(search: searchText, includeArchived: showArchived)
    }

    var body: some View {
        List {
            Section {
                Toggle("Show archived", isOn: $showArchived)
                Button {
                    showCreateFood = true
                } label: {
                    Label("Add Food", systemImage: "plus.circle")
                }
            }

            Section("Foods") {
                ForEach(foods, id: \.id) { food in
                    Button {
                        editingFood = food
                        showEditingFood = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(food.name)
                                    if food.isArchived {
                                        Text("Archived")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.systemGray5))
                                            .clipShape(Capsule())
                                    }
                                }
                                if let brand = food.brand {
                                    Text(brand)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

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
                NutritionFoodEditorView()
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
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nutritionService.meals.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return nutritionService.meals.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showCreateMeal = true
                } label: {
                    Label("Add Meal Template", systemImage: "plus.circle")
                }
            }

            Section("Meals") {
                ForEach(meals, id: \.id) { meal in
                    Button {
                        editingMeal = meal
                        showEditMeal = true
                    } label: {
                        HStack {
                            Text(meal.name)
                            Spacer()
                            Text("\(meal.items.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
    var onSaved: ((Food) -> Void)?

    init(food: Food? = nil, onSaved: ((Food) -> Void)? = nil) {
        self.food = food
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
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $name)
                TextField("Brand (optional)", text: $brand)
                TextField("Reference label (optional)", text: $referenceLabel)
            }

            Section("Reference Amount") {
                TextField("Grams per reference", text: $gramsPerReference)
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
        .navigationTitle(food == nil ? "Add Food" : "Edit Food")
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
        guard let food else { return }
        name = food.name
        brand = food.brand ?? ""
        referenceLabel = food.referenceLabel ?? ""
        gramsPerReference = String(format: "%.0f", food.gramsPerReference)
        kcalPerReference = String(format: "%.0f", food.kcalPerReference)
        proteinPerReference = String(format: "%.0f", food.proteinPerReference)
        carbPerReference = String(format: "%.0f", food.carbPerReference)
        fatPerReference = String(format: "%.0f", food.fatPerReference)
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
                fatPerReference: fat
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
                fatPerReference: fat
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

private struct MealTemplateDraftItem: Identifiable {
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
    @State private var draftItems: [MealTemplateDraftItem] = []
    @State private var showArchivedFoods = false
    @State private var showCreateFood = false
    @State private var showFoodPicker = false
    @State private var editingDraftItemID: UUID?
    @State private var errorText: String?

    init(meal: Meal? = nil, onSaved: ((Meal) -> Void)? = nil) {
        self.meal = meal
        self.onSaved = onSaved
    }

    private var availableFoods: [Food] {
        nutritionService.fetchFoods(search: nil, includeArchived: showArchivedFoods)
    }

    var body: some View {
        List {
            Section("Meal") {
                TextField("Name", text: $name)
            }

            Section("Foods") {
                Toggle("Show archived", isOn: $showArchivedFoods)

                if availableFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No foods yet")
                            .font(.headline)
                        Text("Create a food first to build this template.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Create Food") {
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
                                    Text("Food")
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
            loadInitialValues()
        }
        .sheet(isPresented: $showCreateFood) {
            NavigationStack {
                NutritionFoodEditorView { _ in
                    nutritionService.loadFoods()
                }
            }
            .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showFoodPicker) {
            NutritionFoodPickerView { selectedFood in
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
            if nutritionService.updateMeal(meal, name: name, items: items) {
                onSaved?(meal)
                dismiss()
            } else {
                errorText = "Could not update template."
            }
        } else {
            if let createdMeal = nutritionService.createMealTemplate(name: name, items: items) {
                onSaved?(createdMeal)
                dismiss()
            } else {
                errorText = "Could not create template."
            }
        }
    }
}
