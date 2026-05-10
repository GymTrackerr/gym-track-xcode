import SwiftUI

struct NutritionDayView: View {
    @EnvironmentObject var nutritionService: NutritionService

    @State private var selectedRange: NutritionRangeMode = .today
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
    @State private var periodSummaries: [NutritionDailySummary] = []
    @State private var periodErrorMessage: String?
    @State private var navigationBounds: NutritionNavigationBounds?
    private let showsRangeControls: Bool

    init(initialSelectedDate: Date = Date(), showsRangeControls: Bool = true) {
        let normalizedDate = Calendar.current.startOfDay(for: initialSelectedDate)
        _selectedDate = State(initialValue: normalizedDate)
        self.showsRangeControls = showsRangeControls
    }

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
        VStack(spacing: 0) {
            if showsRangeControls {
                rangeControlRow
            }

            if selectedRange == .today {
                dayContent
            } else {
                periodContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            loadSelectedDay()
            do {
                _ = try nutritionService.getOrCreateTarget()
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
            refreshPeriodSummaries()
            refreshNavigationBounds()
        }
        .onChange(of: selectedDate) {
            let normalizedDate = Calendar.current.startOfDay(for: selectedDate)
            if normalizedDate != selectedDate {
                selectedDate = normalizedDate
                return
            }

            if showDatePickerSheet {
                selectedRange = .today
            }
            loadSelectedDay()
            refreshPeriodSummaries()
        }
        .onChange(of: selectedRange) {
            if selectedRange == .today {
                loadSelectedDay()
            } else {
                refreshPeriodSummaries()
            }
        }
        .sheet(isPresented: $showDatePickerSheet) {
            NutritionDatePickerSheet(selectedDate: $selectedDate)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showLogSheet, onDismiss: {
            refreshPeriodSummaries()
            refreshNavigationBounds()
        }) {
            NutritionLogSheet(selectedDate: selectedDate)
                .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showManagePage) {
            ManageNutritionView().appBackground()
        }
        .sheet(isPresented: $showTargetsSheet) {
            NutritionTargetsView()
                .editorSheetPresentation()
        }
        .sheet(item: $editingLog) { log in
            EditNutritionLogView(log: log, selectedDate: selectedDate)
                .editorSheetPresentation()
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
                    refreshNavigationBounds()
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

    private var rangeControlRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button {
                    showDatePickerSheet = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                        .controlCapsuleSurface()
                }
                .buttonStyle(.plain)

                ForEach(NutritionRangeMode.allCases) { range in
                    FilterPill(
                        title: range.displayName,
                        isSelected: selectedRange == range && (range != .today || isSelectedDateToday)
                    )
                    .onTapGesture {
                        selectRange(range)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .padding(.vertical, 12)
        .screenContentPadding()
    }

    private var dayContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
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
    }

    private var periodContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                periodSummaryCard

                if let periodErrorMessage {
                    EmptyStateView(
                        title: "Couldn't load nutrition summaries",
                        systemImage: "exclamationmark.triangle",
                        message: periodErrorMessage
                    )
                } else if periodSummaries.isEmpty {
                    EmptyStateView(
                        title: "No nutrition logs",
                        systemImage: "fork.knife",
                        message: "Log a meal or food item to see summaries here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(title: periodSectionTitle)

                        ForEach(periodSummaries) { summary in
                            NavigationLink {
                                NutritionDayView(
                                    initialSelectedDate: summary.date,
                                    showsRangeControls: false
                                )
                                .appBackground()
                            } label: {
                                NutritionDailySummaryRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .screenContentPadding()
        }
    }

    private var periodSummaryCard: some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 12) {
                periodSummaryHeader

                Text("Daily averages")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    SummaryMetricTile(
                        title: "Calories",
                        value: "\(Int(periodAverageCalories.rounded())) kcal",
                        systemImage: "flame",
                        tint: .orange
                    )

                    SummaryMetricTile(
                        title: "Protein",
                        value: "\(Int(periodAverageProtein.rounded())) g",
                        systemImage: "bolt",
                        tint: .yellow
                    )

                    SummaryMetricTile(
                        title: "Logs",
                        value: formattedAverageLogs,
                        systemImage: "list.bullet",
                        tint: .blue
                    )
                }
            }
        }
    }

    private var dailySummary: some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 12) {
                daySummaryHeader

                HStack {
                    Text("\(Int(totalKcal.rounded())) kcal")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            showTargetsSheet = true
                        } label: {
                            Label("Target", systemImage: "scope")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showCopyYesterdayConfirmation = true
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 12) {
                    SummaryMetricTile(title: "Protein", value: "\(Int(totalProtein.rounded())) g")
                    SummaryMetricTile(title: "Carbs", value: "\(Int(totalCarbs.rounded())) g")
                    SummaryMetricTile(title: "Fat", value: "\(Int(totalFat.rounded())) g")
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

                if !dailyExtraRows.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(dailyExtraRows, id: \.key) { row in
                            HStack {
                                Text(row.name)
                                Spacer()
                                Text(row.value)
                                    .fontWeight(.semibold)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var dailyExtraRows: [(key: String, name: String, value: String)] {
        nutritionService.visibleNutrientDefinitions().compactMap { definition in
            let key = NutritionNutrientKey.normalized(definition.key)
            let value = nutritionService.totalOptionalNutrient(name: key, for: dayLogs)
            guard value > 0 else { return nil }
            return (key, definition.displayName, "\(displayAmount(value)) \(definition.unitLabel)")
        }
    }

    private var daySummaryHeader: some View {
        HStack(spacing: 10) {
            Button {
                shiftSelectedPeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!canShiftSelectedPeriod(by: -1))

            Spacer()

            VStack(alignment: .center, spacing: 3) {
                Text(periodNavigationTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                shiftSelectedPeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!canShiftSelectedPeriod(by: 1))
        }
    }

    private var periodSummaryHeader: some View {
        HStack(spacing: 10) {
            if selectedRange != .all {
                Button {
                    shiftSelectedPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canShiftSelectedPeriod(by: -1))
            }

            Spacer()

            VStack(alignment: .center, spacing: 3) {
                Text(selectedRange == .all ? periodTitle : periodNavigationTitle)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(selectedRange == .all ? periodSubtitle : selectedRange.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            if selectedRange != .all {
                Button {
                    shiftSelectedPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canShiftSelectedPeriod(by: 1))
            }
        }
    }

    private var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var periodTitle: String {
        switch selectedRange {
        case .today:
            return "Today"
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .all:
            return "All Nutrition"
        }
    }

    private var periodSubtitle: String {
        switch selectedRange {
        case .today:
            return selectedDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDate) else {
                return selectedDate.formatted(date: .abbreviated, time: .omitted)
            }
            let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .all:
            return periodSummaries.isEmpty ? "No logged days yet" : "\(periodSummaries.count) logged day\(periodSummaries.count == 1 ? "" : "s")"
        }
    }

    private var periodNavigationTitle: String {
        switch selectedRange {
        case .today:
            return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .week:
            guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDate) else {
                return selectedDate.formatted(date: .abbreviated, time: .omitted)
            }
            let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .all:
            return "All"
        }
    }

    private var periodSectionTitle: String {
        selectedRange == .all ? "Logged Days" : "Days"
    }

    private var periodAverageCalories: Double {
        guard periodAverageDenominator > 0 else { return 0 }
        return periodSummaries.reduce(0) { $0 + $1.calories } / Double(periodAverageDenominator)
    }

    private var periodAverageProtein: Double {
        guard periodAverageDenominator > 0 else { return 0 }
        return periodSummaries.reduce(0) { $0 + $1.protein } / Double(periodAverageDenominator)
    }

    private var periodAverageLogs: Double {
        guard periodAverageDenominator > 0 else { return 0 }
        return Double(periodSummaries.reduce(0) { $0 + $1.logCount }) / Double(periodAverageDenominator)
    }

    private var periodAverageDenominator: Int {
        periodSummaries.count
    }

    private var formattedAverageLogs: String {
        if periodAverageLogs.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(periodAverageLogs))
        }

        return String(format: "%.1f", periodAverageLogs)
    }

    private func selectRange(_ range: NutritionRangeMode) {
        selectedRange = range

        if range == .today {
            selectedDate = Calendar.current.startOfDay(for: Date())
        }
    }

    private func shiftSelectedPeriod(by value: Int) {
        guard canShiftSelectedPeriod(by: value) else { return }
        guard let shiftedDate = shiftedSelectedDate(by: value) else { return }
        selectedDate = shiftedDate
    }

    private func canShiftSelectedPeriod(by value: Int) -> Bool {
        guard selectedRange != .all, let shiftedDate = shiftedSelectedDate(by: value) else {
            return false
        }

        return isSelectedDateWithinNavigationBounds(shiftedDate, range: selectedRange)
    }

    private func shiftedSelectedDate(by value: Int) -> Date? {
        let calendar = Calendar.current
        let component: Calendar.Component

        switch selectedRange {
        case .today:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .all:
            return nil
        }

        guard let shiftedDate = calendar.date(byAdding: component, value: value, to: selectedDate) else {
            return nil
        }

        return calendar.startOfDay(for: shiftedDate)
    }

    private func loadSelectedDay() {
        nutritionService.loadDayData(for: selectedDate)
    }

    private func refreshNavigationBounds() {
        do {
            let bounds = try nutritionService.nutritionBounds(for: .calories)
            guard let oldest = bounds.oldest else {
                navigationBounds = nil
                return
            }

            navigationBounds = NutritionNavigationBounds(oldest: oldest)
        } catch {
            navigationBounds = nil
        }
    }

    private func isSelectedDateWithinNavigationBounds(_ date: Date, range: NutritionRangeMode) -> Bool {
        let calendar = Calendar.current
        guard let bounds = navigationBounds,
              let periodStart = range.periodStart(for: date, calendar: calendar),
              let oldestPeriodStart = range.periodStart(for: bounds.oldest, calendar: calendar),
              let currentPeriodStart = range.periodStart(for: Date(), calendar: calendar) else {
            return true
        }

        let component = range.calendarComponent
        let minimumAllowedStart = calendar.date(byAdding: component, value: -1, to: oldestPeriodStart) ?? oldestPeriodStart
        let maximumAllowedStart = calendar.date(byAdding: component, value: 1, to: currentPeriodStart) ?? currentPeriodStart

        return periodStart >= minimumAllowedStart && periodStart <= maximumAllowedStart
    }

    private func refreshPeriodSummaries() {
        guard selectedRange != .today else {
            periodSummaries = []
            periodErrorMessage = nil
            return
        }

        let calendar = Calendar.current

        do {
            switch selectedRange {
            case .today:
                periodSummaries = []
            case .week:
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
                    periodSummaries = []
                    return
                }

                let logs = try nutritionService.logsInDateInterval(interval)
                periodSummaries = dailySummaries(
                    from: logs,
                    interval: interval,
                    includeEmptyDays: false,
                    newestFirst: true
                )
            case .month:
                guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else {
                    periodSummaries = []
                    return
                }

                let logs = try nutritionService.logsInDateInterval(interval)
                periodSummaries = dailySummaries(
                    from: logs,
                    interval: interval,
                    includeEmptyDays: false,
                    newestFirst: true
                )
            case .all:
                let bounds = try nutritionService.nutritionBounds(for: .calories)
                guard let oldest = bounds.oldest, let newest = bounds.newest else {
                    periodSummaries = []
                    periodErrorMessage = nil
                    return
                }

                let start = calendar.startOfDay(for: oldest)
                let newestDay = calendar.startOfDay(for: newest)
                let end = calendar.date(byAdding: .day, value: 1, to: newestDay) ?? newestDay
                let interval = DateInterval(start: start, end: end)
                let logs = try nutritionService.logsInDateInterval(interval)
                periodSummaries = dailySummaries(
                    from: logs,
                    interval: interval,
                    includeEmptyDays: false,
                    newestFirst: true
                )
            }

            periodErrorMessage = nil
        } catch {
            periodSummaries = []
            periodErrorMessage = error.localizedDescription
        }
    }

    private func dailySummaries(
        from logs: [NutritionLogEntry],
        interval: DateInterval,
        includeEmptyDays: Bool,
        newestFirst: Bool
    ) -> [NutritionDailySummary] {
        let calendar = Calendar.current
        let groupedLogs = Dictionary(grouping: logs) { log in
            calendar.startOfDay(for: log.timestamp)
        }

        if includeEmptyDays {
            let start = calendar.startOfDay(for: interval.start)
            let end = calendar.startOfDay(for: interval.end)
            let dayCount = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)

            return (0..<dayCount).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                    return nil
                }

                return dailySummary(for: date, logs: groupedLogs[date] ?? [])
            }
        }

        return groupedLogs.keys
            .sorted { newestFirst ? $0 > $1 : $0 < $1 }
            .map { date in
                dailySummary(for: date, logs: groupedLogs[date] ?? [])
            }
    }

    private func dailySummary(for date: Date, logs: [NutritionLogEntry]) -> NutritionDailySummary {
        NutritionDailySummary(
            date: date,
            calories: nutritionService.totalKcal(for: logs),
            protein: nutritionService.totalProtein(for: logs),
            carbs: nutritionService.totalCarbs(for: logs),
            fat: nutritionService.totalFat(for: logs),
            logCount: logs.count
        )
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
                refreshNavigationBounds()
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
                refreshNavigationBounds()
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

    private func displayAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return SetDisplayFormatter.formatDecimal(value)
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

private enum NutritionRangeMode: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today:
            return "Today"
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .all:
            return "All"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .today:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        case .all:
            return .era
        }
    }

    func periodStart(for date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .today:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
        case .all:
            return nil
        }
    }
}

private struct NutritionNavigationBounds {
    let oldest: Date
}

private struct NutritionDailySummary: Identifiable {
    let date: Date
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let logCount: Int

    var id: Date { date }
}

private struct NutritionDailySummaryRow: View {
    let summary: NutritionDailySummary

    var body: some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.date, format: .dateTime.weekday(.wide))
                            .font(.headline)

                        Text(summary.date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(summary.calories.rounded())) kcal")
                            .font(.subheadline.weight(.semibold))

                        Text("\(summary.logCount) log\(summary.logCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    SummaryMetricTile(title: "Protein", value: "\(Int(summary.protein.rounded())) g")
                    SummaryMetricTile(title: "Carbs", value: "\(Int(summary.carbs.rounded())) g")
                    SummaryMetricTile(title: "Fat", value: "\(Int(summary.fat.rounded())) g")
                }
            }
        }
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
                        .controlCapsuleSurface()
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
    @EnvironmentObject var nutritionService: NutritionService

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

                if !extraDescription.isEmpty {
                    Text(extraDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(primaryValueText)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if isQuickAdd {
                    Text(secondaryValueText)
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

    private var primaryValueText: String {
        if log.hasProvidedNutrient(NutritionNutrientKey.calories) {
            return "\(Int(log.caloriesSnapshot.rounded())) kcal"
        }
        if log.hasProvidedNutrient(NutritionNutrientKey.protein) {
            return "P \(displayAmount(log.proteinSnapshot)) g"
        }
        if log.hasProvidedNutrient(NutritionNutrientKey.carbs) {
            return "C \(displayAmount(log.carbsSnapshot)) g"
        }
        if log.hasProvidedNutrient(NutritionNutrientKey.fat) {
            return "F \(displayAmount(log.fatSnapshot)) g"
        }
        return "Unknown"
    }

    private var secondaryValueText: String {
        let parts = [
            log.hasProvidedNutrient(NutritionNutrientKey.protein) ? "P \(displayAmount(log.proteinSnapshot))g" : nil,
            log.hasProvidedNutrient(NutritionNutrientKey.carbs) ? "C \(displayAmount(log.carbsSnapshot))g" : nil,
            log.hasProvidedNutrient(NutritionNutrientKey.fat) ? "F \(displayAmount(log.fatSnapshot))g" : nil
        ].compactMap { $0 }

        return parts.isEmpty ? "Quick Add" : parts.joined(separator: "  ")
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
        if log.logType == .quickCalories {
            return true
        }
        return (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
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
