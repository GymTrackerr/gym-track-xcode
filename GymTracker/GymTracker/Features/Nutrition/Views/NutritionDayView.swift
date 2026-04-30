import SwiftUI

struct NutritionDayView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showDatePickerSheet = false
    @State private var showLogSheet = false
    @State private var showManagePage = false
    @State private var expandedMealLogIDs: Set<UUID> = []
    @State private var editingLog: NutritionLogEntry?
    @State private var showTargetsSheet = false
    @State private var showCopyYesterdayConfirmation = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSaveTemplateAlert = false
    @State private var mealLogToSaveTemplate: NutritionLogEntry?
    @State private var mealTemplateName = ""

    private var dayLogs: [NutritionLogEntry] {
        nutritionService.dayLogs.sorted { $0.timestamp < $1.timestamp }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                dayHeader
                dailySummary

                if dayLogs.isEmpty {
                    EmptyStateView(
                        title: "No logs for this day",
                        systemImage: "fork.knife",
                        message: "Add food, quick calories, or a meal to start tracking this day."
                    )
                } else {
                    logSections
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    NutritionHistoryChartView()
                        .appBackground()
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLogSheet = true
                } label: {
                    Label("Log", systemImage: "plus.circle")
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
                .presentationDetents([.large])
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
            EditNutritionLogView(log: log, selectedDate: selectedDate)
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
                guard let mealLogToSaveTemplate else { return }
                do {
                    _ = try nutritionService.createMealTemplate(from: mealLogToSaveTemplate, name: mealTemplateName)
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
                self.mealLogToSaveTemplate = nil
            }
            Button("Cancel", role: .cancel) {
                mealLogToSaveTemplate = nil
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
        ConnectedCardSection {
            ConnectedCardRow {
                HStack(spacing: 10) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        showDatePickerSheet = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Text(selectedDate, format: .dateTime.month(.abbreviated).day().year())
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCopyYesterdayConfirmation = true
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dailySummary: some View {
        CardRowContainer {
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
        }
    }

    private var logSections: some View {
        ForEach(FoodLogCategory.displayOrder) { category in
            let standalone = standaloneLogs(for: category)
            let meals = mealLogs(for: category)

            if !standalone.isEmpty || !meals.isEmpty {
                nutritionCategorySection(
                    category: category,
                    standalone: standalone,
                    meals: meals
                )
            }
        }
    }

    @ViewBuilder
    private func nutritionCategorySection(
        category: FoodLogCategory,
        standalone: [NutritionLogEntry],
        meals: [NutritionLogEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: category.displayName)

            ConnectedCardSection {
                let combinedCount = standalone.count + meals.count

                ForEach(Array(standalone.enumerated()), id: \.element.id) { index, log in
                    foodLogRow(log)

                    if index < combinedCount - 1 {
                        ConnectedCardDivider(leadingInset: 14)
                    }
                }

                ForEach(Array(meals.enumerated()), id: \.element.id) { index, log in
                    mealLogRow(log)

                    if standalone.count + index < combinedCount - 1 {
                        ConnectedCardDivider(leadingInset: 14)
                    }
                }
            }
        }
    }

    private func foodLogRow(_ log: NutritionLogEntry) -> some View {
        ConnectedCardRow {
            NutritionLogRow(log: log)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingLog = log
        }
        .contextMenu {
            Button {
                editingLog = log
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                nutritionService.deleteFoodLog(log, selectedDate: selectedDate)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func mealLogRow(_ log: NutritionLogEntry) -> some View {
        let isExpanded = expandedMealLogIDs.contains(log.id)

        return ConnectedCardRow {
            VStack(alignment: .leading, spacing: 10) {
                NutritionMealLogHeaderRow(
                    log: log,
                    isExpanded: isExpanded,
                    onSaveAsTemplate: {
                        mealLogToSaveTemplate = log
                        mealTemplateName = log.nameSnapshot
                        showSaveTemplateAlert = true
                    }
                )

                if isExpanded {
                    mealSnapshotRows(for: log)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleMealLog(log.id)
        }
        .contextMenu {
            Button {
                mealLogToSaveTemplate = log
                mealTemplateName = log.nameSnapshot
                showSaveTemplateAlert = true
            } label: {
                Label("Save as Template", systemImage: "tray.and.arrow.down")
            }

            Button(role: .destructive) {
                nutritionService.deleteMealEntry(log, selectedDate: selectedDate)
                expandedMealLogIDs.remove(log.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func mealSnapshotRows(for log: NutritionLogEntry) -> some View {
        let items = log.recipeItemsSnapshot ?? []

        if items.isEmpty {
            Text("No meal item snapshot available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
        } else {
            let displayScale = recipeItemDisplayScale(for: log, items: items)

            Divider()
                .padding(.leading, 24)

            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    RecipeItemSnapshotRow(item: item, scale: displayScale)
                }
            }
            .padding(.leading, 24)
        }
    }

    private func standaloneLogs(for category: FoodLogCategory) -> [NutritionLogEntry] {
        dayLogs.filter { $0.category == category && $0.logType != .meal }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func mealLogs(for category: FoodLogCategory) -> [NutritionLogEntry] {
        dayLogs.filter { $0.category == category && $0.logType == .meal }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func toggleMealLog(_ id: UUID) {
        if expandedMealLogIDs.contains(id) {
            expandedMealLogIDs.remove(id)
        } else {
            expandedMealLogIDs.insert(id)
        }
    }

    private func recipeItemDisplayScale(for log: NutritionLogEntry, items: [RecipeItemSnapshot]) -> Double {
        let snapshotCaloriesTotal = items.reduce(0) { $0 + $1.caloriesSnapshot }
        if snapshotCaloriesTotal > 0 {
            return max(0, log.caloriesSnapshot / snapshotCaloriesTotal)
        }

        let snapshotProteinTotal = items.reduce(0) { $0 + $1.proteinSnapshot }
        if snapshotProteinTotal > 0 {
            return max(0, log.proteinSnapshot / snapshotProteinTotal)
        }

        let snapshotCarbsTotal = items.reduce(0) { $0 + $1.carbsSnapshot }
        if snapshotCarbsTotal > 0 {
            return max(0, log.carbsSnapshot / snapshotCarbsTotal)
        }

        let snapshotFatTotal = items.reduce(0) { $0 + $1.fatSnapshot }
        if snapshotFatTotal > 0 {
            return max(0, log.fatSnapshot / snapshotFatTotal)
        }

        return 1
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

private struct NutritionMealLogHeaderRow: View {
    let log: NutritionLogEntry
    let isExpanded: Bool
    let onSaveAsTemplate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.75))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(log.nameSnapshot)
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

                Text(log.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(log.caloriesSnapshot.rounded())) kcal")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(displayAmount(log.amount)) \(log.servingUnitLabelSnapshot ?? log.amountUnitSnapshot)")
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
    }

    private func displayAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }
}

private struct NutritionLogRow: View {
    let log: NutritionLogEntry

    private var isQuickAdd: Bool {
        log.logType == .quickCalories
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.nameSnapshot)
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
                Text("\(Int(log.caloriesSnapshot.rounded())) kcal")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if isQuickAdd {
                    Text("Quick Add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(displayAmount(log.amount)) \(log.amountUnitSnapshot)")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.75))
                }
            }
        }
    }

    private func displayAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }
}

private struct RecipeItemSnapshotRow: View {
    let item: RecipeItemSnapshot
    let scale: Double

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                Text("\(displayAmount(item.amount * scale)) \(item.amountUnit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int((item.caloriesSnapshot * scale).rounded())) kcal")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("P \(Int((item.proteinSnapshot * scale).rounded()))  C \(Int((item.carbsSnapshot * scale).rounded()))  F \(Int((item.fatSnapshot * scale).rounded()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return SetDisplayFormatter.formatDecimal(value)
    }
}

private struct NutritionDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                CardRowContainer {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
                .screenContentPadding()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        selectedDate = Calendar.current.startOfDay(for: Date())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
                    TextField("Calories", text: $calories).keyboardType(.decimalPad)
                    TextField("Protein", text: $protein).keyboardType(.decimalPad)
                    TextField("Carbs", text: $carbs).keyboardType(.decimalPad)
                    TextField("Fat", text: $fat).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Nutrition Targets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
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

private struct EditNutritionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var nutritionService: NutritionService

    let log: NutritionLogEntry
    let selectedDate: Date

    @State private var amount = ""
    @State private var note = ""
    @State private var category: FoodLogCategory = .other
    @State private var selectedTime: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    Text(log.nameSnapshot)
                }

                Section("Edit") {
                    TextField("Amount", text: $amount)
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
                amount = String(format: "%.2f", log.amount)
                note = log.note ?? ""
                category = log.category
                selectedTime = log.timestamp
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let pinnedTimestamp = nutritionService.dateByPinning(selectedTime, to: selectedDate)

        let didSave = nutritionService.updateFoodLog(
            log,
            amount: amountValue,
            timestamp: pinnedTimestamp,
            category: category,
            note: note
        )

        if didSave {
            dismiss()
        }
    }
}
