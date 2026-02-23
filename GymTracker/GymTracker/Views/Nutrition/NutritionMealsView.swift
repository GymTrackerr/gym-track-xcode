import SwiftUI

struct NutritionMealsView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var showCreateMeal = false
    @State private var editingMeal: Meal?

    var body: some View {
        NavigationStack {
            List {
                if nutritionService.meals.isEmpty {
                    ContentUnavailableView("No meal templates", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(nutritionService.meals, id: \.id) { meal in
                        Button {
                            editingMeal = meal
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name)
                                        .font(.body)
                                        .fontWeight(.medium)

                                    Text("\(meal.items.count) item\(meal.items.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
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
            .navigationTitle("Meals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateMeal = true
                    } label: {
                        Label("Create Meal", systemImage: "plus")
                    }
                }
            }
            .onAppear {
                nutritionService.loadMeals()
                nutritionService.loadFoods()
            }
            .sheet(isPresented: $showCreateMeal) {
                NutritionMealEditorView()
                    .presentationDetents([.large])
            }
            .sheet(item: $editingMeal) { meal in
                NutritionMealEditorView(meal: meal)
                    .presentationDetents([.large])
            }
        }
    }
}

struct NutritionLogMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let selectedDate: Date

    @State private var selectedMeal: Meal?
    @State private var category: FoodLogCategory = .other
    @State private var selectedTime: Date = Date()
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    if nutritionService.meals.isEmpty {
                        Text("Create a meal template first")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Template", selection: $selectedMeal) {
                            ForEach(nutritionService.meals, id: \.id) { meal in
                                Text(meal.name).tag(Optional(meal))
                            }
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

                if let selectedMeal {
                    Section("Template Items") {
                        ForEach(selectedMeal.items.sorted(by: { $0.order < $1.order }), id: \.id) { item in
                            HStack {
                                Text(item.food.name)
                                Spacer()
                                Text("\(Int(item.grams.rounded())) g")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log Meal")
            .onAppear {
                nutritionService.loadMeals()
                category = nutritionService.defaultCategory(for: Date())
                selectedTime = Date()
                if selectedMeal == nil {
                    selectedMeal = nutritionService.meals.first
                }
            }
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
                    .disabled(selectedMeal == nil)
                }
            }
        }
    }

    private func save() {
        guard let selectedMeal else { return }

        let pinnedTimestamp = nutritionService.dateByPinning(selectedTime, to: selectedDate)
        do {
            _ = try nutritionService.logMeal(
                template: selectedMeal,
                timestamp: pinnedTimestamp,
                category: category,
                note: note
            )
            dismiss()
        } catch {
            // Keep legacy view behavior minimal; unified flow surfaces errors.
        }
    }
}

private struct MealDraftItem: Identifiable {
    let id: UUID
    var foodId: UUID?
    var gramsText: String

    init(id: UUID = UUID(), foodId: UUID? = nil, gramsText: String = "") {
        self.id = id
        self.foodId = foodId
        self.gramsText = gramsText
    }
}

struct NutritionMealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let meal: Meal?

    @State private var name: String = ""
    @State private var draftItems: [MealDraftItem] = []

    init(meal: Meal? = nil) {
        self.meal = meal
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Meal") {
                    TextField("Name", text: $name)
                }

                Section("Items") {
                    if nutritionService.foods.isEmpty {
                        Text("Add foods first")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($draftItems) { $item in
                            VStack(spacing: 8) {
                                Picker("Food", selection: $item.foodId) {
                                    Text("Select food").tag(Optional<UUID>.none)
                                    ForEach(nutritionService.foods, id: \.id) { food in
                                        Text(food.name).tag(Optional(food.id))
                                    }
                                }

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
                            draftItems.append(MealDraftItem())
                        } label: {
                            Label("Add Item", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle(meal == nil ? "Create Meal" : "Edit Meal")
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

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .onAppear {
                nutritionService.loadFoods()
                loadInitialValues()
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !resolvedItems().isEmpty
    }

    private func loadInitialValues() {
        guard let meal else {
            if draftItems.isEmpty {
                draftItems = [MealDraftItem()]
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
                    MealDraftItem(
                        id: $0.id,
                        foodId: $0.food.id,
                        gramsText: String(format: "%.0f", $0.grams)
                    )
                }

            if draftItems.isEmpty {
                draftItems = [MealDraftItem()]
            }
        }
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
        guard !items.isEmpty else { return }

        if let meal {
            if nutritionService.updateMeal(meal, name: name, items: items) {
                dismiss()
            }
        } else {
            if nutritionService.addMeal(name: name, items: items) != nil {
                dismiss()
            }
        }
    }
}
