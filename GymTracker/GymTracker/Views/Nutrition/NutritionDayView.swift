import SwiftUI

struct NutritionDayView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showDatePickerSheet = false
    @State private var showLogSheet = false
    @State private var showManagePage = false
    @State private var expandedMealEntryIDs: Set<UUID> = []
    @State private var editingLog: FoodLog?
    @State private var showTargetsSheet = false
    @State private var showCopyYesterdayConfirmation = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSaveTemplateAlert = false
    @State private var mealEntryToSaveTemplate: MealEntry?
    @State private var mealTemplateName = ""

    private var dayLogs: [FoodLog] {
        nutritionService.dayLogs.sorted { $0.timestamp < $1.timestamp }
    }

    private var dayMealEntries: [MealEntry] {
        nutritionService.dayMealEntries.sorted { $0.timestamp < $1.timestamp }
    }

    private var totalKcal: Double {
        nutritionService.totalKcal(for: dayLogs)
    }

    private var totalProtein: Double {
        nutritionService.totalProtein(for: dayLogs)
    }

    private var totalCarbs: Double {
        nutritionService.totalCarbs(for: dayLogs)
    }

    private var totalFat: Double {
        nutritionService.totalFat(for: dayLogs)
    }

    private var activeTarget: NutritionTarget? {
        nutritionService.nutritionTarget
    }

    private var isTargetEnabled: Bool {
        activeTarget?.isEnabled == true
    }

    private var remainingCalories: Double {
        guard let target = activeTarget, target.calorieTarget > 0 else { return 0 }
        return max(0, target.calorieTarget - totalKcal)
    }

    private var remainingProtein: Double? {
        guard let target = activeTarget, target.proteinTarget > 0 else { return nil }
        return max(0, target.proteinTarget - totalProtein)
    }

    private var remainingCarbs: Double? {
        guard let target = activeTarget, target.carbTarget > 0 else { return nil }
        return max(0, target.carbTarget - totalCarbs)
    }

    private var remainingFat: Double? {
        guard let target = activeTarget, target.fatTarget > 0 else { return nil }
        return max(0, target.fatTarget - totalFat)
    }

    var body: some View {
        VStack(spacing: 12) {
            dayHeader

            dailySummary

            if dayLogs.isEmpty {
                ContentUnavailableView("No logs for this day", systemImage: "fork.knife")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(FoodLogCategory.displayOrder) { category in
                        let standaloneLogs = standaloneLogs(for: category)
                        let categoryMealEntries = mealEntries(for: category)

                        if !standaloneLogs.isEmpty || !categoryMealEntries.isEmpty {
                            Section {
                                ForEach(standaloneLogs, id: \.id) { log in
                                    NutritionLogRow(log: log)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingLog = log
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                nutritionService.deleteFoodLog(log, selectedDate: selectedDate)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }

                                ForEach(categoryMealEntries, id: \.id) { entry in
                                    let isExpanded = expandedMealEntryIDs.contains(entry.id)
                                    VStack(alignment: .leading, spacing: 8) {
                                        NutritionMealEntryHeaderRow(
                                            entry: entry,
                                            logs: logs(for: entry),
                                            isExpanded: isExpanded,
                                            onSaveAsTemplate: {
                                                mealEntryToSaveTemplate = entry
                                                mealTemplateName = entry.templateMeal?.name ?? "Saved Meal"
                                                showSaveTemplateAlert = true
                                            }
                                        )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                toggleMealEntry(entry.id)
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    nutritionService.deleteMealEntry(entry, selectedDate: selectedDate)
                                                    expandedMealEntryIDs.remove(entry.id)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }

                                        if isExpanded {
                                            Divider()
                                                .padding(.leading, 12)
                                                .padding(.bottom, 4)

                                            VStack(spacing: 10) {
                                                ForEach(logs(for: entry), id: \.id) { log in
                                                    NutritionLogRow(log: log)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            editingLog = log
                                                        }
                                                }
                                            }
                                            .padding(.top, 3)
                                            .transition(.opacity)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            } header: {
                                Text(category.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                                    .padding(.top, 14)
                            }
                            .listRowBackground(Color(.secondarySystemBackground).opacity(0.74))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.top, 8)
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLogSheet = true
                } label: {
                    Label("Log Food", systemImage: "plus.circle")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showManagePage = true
                } label: {
                    Label("Manage", systemImage: "line.3.horizontal")
                }
            }
        }
        .onAppear {
            nutritionService.loadFoods()
            nutritionService.loadMeals()
            nutritionService.loadDayData(for: selectedDate)
            do {
                _ = try nutritionService.getOrCreateTarget()
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
        .onChange(of: selectedDate) {
            selectedDate = Calendar.current.startOfDay(for: selectedDate)
            nutritionService.loadDayData(for: selectedDate)
        }
        .sheet(isPresented: $showDatePickerSheet) {
            NutritionDatePickerSheet(selectedDate: $selectedDate)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLogSheet) {
            NutritionLogSheet(selectedDate: selectedDate)
                .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showManagePage) {
            ManageNutritionView().appBackground()
        }
        .sheet(isPresented: $showTargetsSheet) {
            NutritionTargetsView()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingLog) { log in
            EditFoodLogView(log: log, selectedDate: selectedDate)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Copy yesterday's standalone items into this day?",
            isPresented: $showCopyYesterdayConfirmation,
            titleVisibility: .visible
        ) {
            Button("Copy Yesterday") {
                do {
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    _ = try nutritionService.copyStandaloneLogs(from: yesterday, to: selectedDate)
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Save as Template", isPresented: $showSaveTemplateAlert) {
            TextField("Template Name", text: $mealTemplateName)
            Button("Save") {
                guard let mealEntryToSaveTemplate else { return }
                do {
                    _ = try nutritionService.createMealTemplate(from: mealEntryToSaveTemplate, name: mealTemplateName)
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
                self.mealEntryToSaveTemplate = nil
            }
            Button("Cancel", role: .cancel) {
                mealEntryToSaveTemplate = nil
            }
        } message: {
            Text("Create a reusable template from this logged meal.")
        }
        .alert("Couldn't Complete Action", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 12) {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }

            Spacer()

            Text(selectedDate, format: .dateTime.month(.abbreviated).day().year())
                .font(.headline)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }

            Button {
                showDatePickerSheet = true
            } label: {
                Image(systemName: "calendar")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }

            Button {
                showCopyYesterdayConfirmation = true
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal)
    }

    private var dailySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Int(totalKcal.rounded())) kcal")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showTargetsSheet = true
                } label: {
                    Label("Target", systemImage: "scope")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                NutritionMacroChip(title: "Protein", value: totalProtein)
                NutritionMacroChip(title: "Carbs", value: totalCarbs)
                NutritionMacroChip(title: "Fat", value: totalFat)
            }

            if isTargetEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remaining: \(Int(remainingCalories.rounded())) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        if let remainingProtein {
                            Text("P \(Int(remainingProtein.rounded()))g")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let remainingCarbs {
                            Text("C \(Int(remainingCarbs.rounded()))g")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let remainingFat {
                            Text("F \(Int(remainingFat.rounded()))g")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func standaloneLogs(for category: FoodLogCategory) -> [FoodLog] {
        dayLogs
            .filter { $0.category == category && $0.mealEntry == nil }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func mealEntries(for category: FoodLogCategory) -> [MealEntry] {
        dayMealEntries
            .filter { $0.category == category }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func logs(for entry: MealEntry) -> [FoodLog] {
        dayLogs
            .filter { $0.mealEntry?.id == entry.id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func toggleMealEntry(_ id: UUID) {
        if expandedMealEntryIDs.contains(id) {
            expandedMealEntryIDs.remove(id)
        } else {
            expandedMealEntryIDs.insert(id)
        }
    }
}

private struct NutritionMacroChip: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(Int(value.rounded())) g")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NutritionMealEntryHeaderRow: View {
    let entry: MealEntry
    let logs: [FoodLog]
    let isExpanded: Bool
    let onSaveAsTemplate: () -> Void

    private var totalKcal: Int {
        Int(logs.reduce(0) { $0 + $1.kcal }.rounded())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.75))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.templateMeal?.name ?? "Meal")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Meal")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.secondary.opacity(0.75))
                        .background(Color(.systemGray5).opacity(0.55))
                        .clipShape(Capsule())
                }

                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalKcal) kcal")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(logs.count) item\(logs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.75))
            }

            Menu {
                Button("Save as Template") {
                    onSaveAsTemplate()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NutritionLogRow: View {
    let log: FoodLog

    private var isQuickAdd: Bool {
        log.quickCaloriesKcal != nil
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isQuickAdd ? "Quick Calories" : log.food.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(log.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.75))

                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(log.kcal.rounded())) kcal")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if isQuickAdd {
                    Text("Quick Add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Int(log.grams.rounded())) \(log.food.unit.shortLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.75))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NutritionDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()

                Spacer()
            }
            .navigationTitle("Select Date")
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

private struct NutritionTargetsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    @State private var isEnabled = false
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Targets") {
                    Toggle("Enable Targets", isOn: $isEnabled)
                    TextField("Calories", text: $calories)
                        .keyboardType(.decimalPad)
                    TextField("Protein", text: $protein)
                        .keyboardType(.decimalPad)
                    TextField("Carbs", text: $carbs)
                        .keyboardType(.decimalPad)
                    TextField("Fat", text: $fat)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Nutrition Targets")
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
                do {
                    let target = try nutritionService.getOrCreateTarget()
                    isEnabled = target.isEnabled
                    calories = numberString(target.calorieTarget)
                    protein = numberString(target.proteinTarget)
                    carbs = numberString(target.carbTarget)
                    fat = numberString(target.fatTarget)
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
            .alert("Couldn't Save", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func save() {
        let calorieValue = parseValue(calories)
        let proteinValue = parseValue(protein)
        let carbsValue = parseValue(carbs)
        let fatValue = parseValue(fat)

        do {
            try nutritionService.updateTarget(
                calories: calorieValue,
                protein: proteinValue,
                carbs: carbsValue,
                fat: fatValue,
                enabled: isEnabled
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func parseValue(_ text: String) -> Double {
        max(0, Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }

    private func numberString(_ value: Double) -> String {
        value == 0 ? "" : String(Int(value.rounded()))
    }
}

private struct EditFoodLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let log: FoodLog
    let selectedDate: Date

    @State private var grams = ""
    @State private var note = ""
    @State private var category: FoodLogCategory = .other
    @State private var selectedTime: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    Text(log.food.name)
                }

                Section("Edit") {
                    TextField("Grams", text: $grams)
                        .keyboardType(.decimalPad)

                    Picker("Category", selection: $category) {
                        ForEach(FoodLogCategory.displayOrder) { item in
                            Text(item.displayName).tag(item)
                        }
                    }

                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)

                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Edit Log")
            .onAppear {
                grams = String(format: "%.0f", log.grams)
                note = log.note ?? ""
                category = log.category
                selectedTime = log.timestamp
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
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        (Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private func save() {
        let gramsValue = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0
        let pinnedTimestamp = nutritionService.dateByPinning(selectedTime, to: selectedDate)

        let didSave = nutritionService.updateFoodLog(
            log,
            grams: gramsValue,
            timestamp: pinnedTimestamp,
            category: category,
            note: note
        )

        if didSave {
            dismiss()
        }
    }
}
