import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var hkManager: HealthKitManager
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var openedSession: Session? = nil
    @State private var showEditMenu: Bool = false
    
    var body: some View {
        Group {
            if userService.currentUser != nil {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        DashboardGridView(openedSession: $openedSession)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Text("Please continue to onboarding")
            }
        }
        .task(id: userService.currentUser?.id) {
            guard userService.currentUser?.isDemo != true else { return }
            await hkManager.requestAuthorization()
            await hkManager.fetchWorkouts()
            guard let userId = userService.currentUser?.id.uuidString else { return }
            await healthKitDailyStore.refreshTodayIfNeeded(userId: userId)
            _ = try? await healthKitDailyStore.dailySummaries(
                endingOn: Date(),
                days: 7,
                userId: userId,
                policy: .refreshIfStale
            )
        }
        .navigationTitle(userService.currentUser != nil ? "Welcome \(userService.currentUser!.name)" : "Home" )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: { showEditMenu = true }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditMenu) {
            DashboardEditView(isPresented: $showEditMenu)
        }
    }
}

struct DashboardGridView: View {
    @EnvironmentObject var dashboardService: DashboardService
    @EnvironmentObject var userService: UserService
    @Binding var openedSession: Session?
    
    var visibleModules: [DashboardModule] {
        dashboardService.getVisibleModules()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if userService.currentUser?.allowHealthAccess ?? false {
                if visibleModules.isEmpty {
                    EmptyDashboardView()
                } else {
                    DashboardModulesView(visibleModules: visibleModules)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Health Data Not Available")
                        .font(.headline)
                    Text("Please enable HealthKit access in Settings to see your dashboard")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Sessions")
                    .font(.headline)

                SessionsView(openedSession: $openedSession)
            }
        }
    }
}

struct EmptyDashboardView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No Dashboard Modules")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Tap Edit to add modules")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

struct DashboardModulesView: View {
    let visibleModules: [DashboardModule]

    var body: some View {
        let spacing: CGFloat = 12
        let padding: CGFloat = 32
        let screenWidth = UIScreen.main.bounds.width
        let availableWidth = screenWidth - padding
        let cellSize = (availableWidth - spacing) / 2
        let smallCellHeight: CGFloat = cellSize * 0.55 // 45% shorter for compact small tiles
        
        DashboardModulesList(
            visibleModules: visibleModules,
            cellSize: cellSize,
            smallCellHeight: smallCellHeight
        )
    }
}

struct DashboardModulesList: View {
    let visibleModules: [DashboardModule]
    let cellSize: CGFloat
    let smallCellHeight: CGFloat
    
    var body: some View {
        let rows = buildModuleRows()
        VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                let row = rows[rowIndex]
                
                if let module = row.module {
                    DashboardFullWidthModule(module: module, cellSize: cellSize, smallCellHeight: smallCellHeight)
                } else if !row.smallModules.isEmpty {
                    DashboardSmallModulesGrid(modules: row.smallModules, cellSize: smallCellHeight)
                }
            }
        }
    }
    
    private func buildModuleRows() -> [ModuleRow] {
        var rows: [ModuleRow] = []
        var smallBuffer: [DashboardModule] = []
        
        for (index, module) in visibleModules.enumerated() {
            let isFullWidth = module.size == .medium || module.size == .large
            let isLastModule = index == visibleModules.count - 1
            let nextIsFullWidth = !isLastModule && (visibleModules[index + 1].size == .medium || visibleModules[index + 1].size == .large)
            
            if isFullWidth {
                if !smallBuffer.isEmpty {
                    rows.append(ModuleRow(smallModules: smallBuffer, module: nil))
                    smallBuffer = []
                }
                rows.append(ModuleRow(smallModules: [], module: module))
            } else {
                smallBuffer.append(module)
                
                if nextIsFullWidth || isLastModule {
                    rows.append(ModuleRow(smallModules: smallBuffer, module: nil))
                    smallBuffer = []
                }
            }
        }
        
        return rows
    }
    
    struct ModuleRow {
        let smallModules: [DashboardModule]
        let module: DashboardModule?
    }
}

struct DashboardSmallModulesGrid: View {
    let modules: [DashboardModule]
    let cellSize: CGFloat
    
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(modules, id: \.id) { module in
                ModuleDisplayView(module: module)
                    .frame(height: cellSize, alignment: .topLeading)
                    .glassEffect(in: .rect(cornerRadius: 12.0))
            }
        }
    }
}

struct DashboardFullWidthModule: View {
    let module: DashboardModule
    let cellSize: CGFloat
    let smallCellHeight: CGFloat
    
    var body: some View {
        ModuleDisplayView(module: module)
            .frame(
                height: getHeight(for: module.size),
                alignment: .topLeading
            )
            .glassEffect(in: .rect(cornerRadius: 12.0))
    }
    
    private func getHeight(for size: ModuleSize) -> CGFloat {
        switch size {
        case .small:
            return smallCellHeight
        case .medium:
            return cellSize
        case .large:
            return cellSize * 2 + 12
        }
    }
}

struct ModuleDisplayView: View {
    let module: DashboardModule
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: module.type.iconName)
                    .foregroundColor(.secondary)
                    .font(.body)
                
                Text(module.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            
            Divider()
            
            DashboardModuleContent(module: module)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
        }
    }
}

struct DashboardModuleContent: View {
    let module: DashboardModule
    
    var body: some View {
        switch module.type {
        case .currentWeight:
            CurrentWeightModuleView()
        case .weeklySteps:
            WeeklyStepsModuleView(module: module)
        case .sleep:
            SleepModuleView()
        case .activityRings:
            ActivityRingsModuleView()
        case .timer:
            TimerModuleView()
        case .fitnessWorkouts:
            FitnessWorkoutsModuleView()
        case .truesight:
            FitSightModuleView(module: module)
        case .nutrition:
            NutritionModuleView(module: module)
        case .sessionVolume:
            SessionVolumeModuleView(module: module)
        }
    }
}

struct FitSightModuleView: View {
    let module: DashboardModule
    
    var body: some View {
        NavigationLink(destination: TrueSightView().appBackground()) {
            MetricCard(
                title: module.type.displayName,
                value: "View",
                icon: module.type.iconName,
                hasBackground: false
            )
        }
       
    }
}

struct NutritionModuleView: View {
    let module: DashboardModule
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthMetricsService: HealthMetricsService
    @State private var deficitSurplus: Double?

    var body: some View {
        if module.size == .medium || module.size == .large {
            NutritionWeeklyCaloriesModule(module: module)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        } else {
            NavigationLink(destination: NutritionDayView().appBackground()) {
                MetricCard(
                    title: module.type.displayName,
                    value: smallCardValue,
                    icon: module.type.iconName,
                    pageNav: true,
                    hasBackground: false
                )
            }
            .task(id: userService.currentUser?.id) {
                await loadDeficit()
            }
        }
    }

    private var smallCardValue: String {
        guard let deficitSurplus else { return "Loading..." }
        let rounded = Int(deficitSurplus.rounded())
        let prefix = rounded >= 0 ? "+" : ""
        return "\(prefix)\(rounded) kcal"
    }

    private func loadDeficit() async {
        guard let userId = healthMetricsService.currentUser?.id.uuidString else {
            deficitSurplus = nil
            return
        }
        deficitSurplus = nil
        deficitSurplus = try? await healthMetricsService.deficitSurplus(for: Date(), userId: userId)
    }
}

struct CurrentWeightModuleView: View {
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @EnvironmentObject var userService: UserService
    @State private var currentWeight: Double?
    
    var body: some View {
        MetricCard(
            title: "Current Weight",
            value: currentWeight.map { String(format: "%.1f", $0) } ?? "N/A",
            icon: "lock.fill",
            hasBackground: false
        )
        .task(id: userService.currentUser?.id) {
            await loadCurrentWeight()
        }
    }

    private func loadCurrentWeight() async {
        guard let userId = userService.currentUser?.id.uuidString else {
            currentWeight = nil
            return
        }
        currentWeight = nil
        let summary = try? await healthKitDailyStore.dailySummary(
            for: Date(),
            userId: userId,
            policy: .refreshIfStale
        )
        currentWeight = summary?.bodyWeightKg
    }
}

struct WeeklyStepsModuleView: View {
    let module: DashboardModule
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @State private var weeklyStepsTotal: Double = 0
    
    var body: some View {
        if module.size == .medium || module.size == .large {
            NavigationLink(destination: HealthHistoryChartView().appBackground()) {
                StepBarGraph(
                    height: module.size == .large ? 165 : 120,
                    barColor: .blue
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        } else {
            NavigationLink(destination: HealthHistoryChartView().appBackground()) {
                MetricCard(
                    title: "Weekly Steps",
                    value: String(weeklyStepsTotal.rounded()),
                    icon: "figure.walk.motion",
                    hasBackground: false
                )
            }
            .task(id: userService.currentUser?.id) {
                await loadWeeklyTotal()
            }
        }
    }

    private func loadWeeklyTotal() async {
        guard let userId = userService.currentUser?.id.uuidString else {
            weeklyStepsTotal = 0
            return
        }
        weeklyStepsTotal = 0
        let summaries = try? await healthKitDailyStore.dailySummaries(
            endingOn: Date(),
            days: 7,
            userId: userId,
            policy: .refreshIfStale
        )
        weeklyStepsTotal = summaries?.reduce(0, { $0 + $1.steps }) ?? 0
    }
}

struct SleepModuleView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @State private var sleepHours: Double?
    
    var body: some View {
        Group {
            if let sleepHours {
                MetricCard(
                    title: "Sleep",
                    value: String(format: "%.1f", sleepHours) + " hrs",
                    icon: "bed.double",
                    alignment: .center,
                    hasBackground: false
                )
            } else {
                MetricCard(
                    title: "Sleep",
                    value: "N/A",
                    icon: "bed.double",
                    alignment: .center,
                    hasBackground: false
                )
            }
        }
        .task(id: userService.currentUser?.id) {
            await loadSleep()
        }
    }

    private func loadSleep() async {
        guard let userId = userService.currentUser?.id.uuidString else {
            sleepHours = nil
            return
        }
        sleepHours = nil
        let summary = try? await healthKitDailyStore.dailySummary(
            for: Date(),
            userId: userId,
            policy: .refreshIfStale
        )
        guard let sleepSeconds = summary?.sleepSeconds, sleepSeconds > 0 else {
            sleepHours = nil
            return
        }
        sleepHours = sleepSeconds / 3600
    }
}

struct ActivityRingsModuleView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @State private var ringStatus: ActivityRingStatus?
    
    var body: some View {
        Group {
            if let ars = ringStatus {
                MetricActivityRingCard(
                    title: "Activity Rings",
                    activityRings: ars,
                    alignment: .center,
                    hasBackground: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                MetricCard(
                    title: "Activity Rings",
                    value: "Loading...",
                    icon: "gauge.with.needle",
                    alignment: .center,
                    hasBackground: false
                )
            }
        }
        .task(id: userService.currentUser?.id) {
            await loadRingStatus()
        }
    }

    private func loadRingStatus() async {
        guard let userId = userService.currentUser?.id.uuidString else {
            ringStatus = nil
            return
        }
        ringStatus = nil
        let summary = try? await healthKitDailyStore.dailySummary(
            for: Date(),
            userId: userId,
            policy: .refreshIfStale
        )
        guard let summary else {
            ringStatus = nil
            return
        }

        ringStatus = ActivityRingStatus(
            moveRingValue: summary.activeEnergyKcal,
            moveRingGoal: max(summary.moveGoalKcal ?? 520, 1),
            exerciseRingValue: summary.exerciseMinutes ?? 0,
            exerciseRingGoal: max(summary.exerciseGoalMinutes ?? 30, 1),
            standRingValue: summary.standHours ?? 0,
            standRingGoal: max(summary.standGoalHours ?? 12, 1)
        )
    }
}

struct TimerModuleView: View {
    @EnvironmentObject var timerService: TimerService
    
    var body: some View {
        NavigationLink(destination: TimerView().appBackground()) {
            MetricCard(
                title: timerService.timer != nil ? "Timer" : "Start Timer",
                value: timerService.timer != nil ? timerService.formatted : "--:--",
                icon: "timer",
                pageNav: true,
                hasBackground: false
            )
        }
    }
}

struct FitnessWorkoutsModuleView: View {
    @EnvironmentObject var hkManager: HealthKitManager
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var sessionService: SessionService
    
    var body: some View {
        NavigationLink(destination: destinationView) {
            MetricCard(
                title: "Fitness Workouts",
                value: String(workoutCount),
                icon: "figure.strengthtraining.traditional",
                pageNav: true,
                hasBackground: false
            )
        }
    }

    private var workoutCount: Int {
        if userService.currentUser?.isDemo == true {
            return sessionService.sessions.count
        }
        return hkManager.workouts.count
    }

    @ViewBuilder
    private var destinationView: some View {
        if userService.currentUser?.isDemo == true {
            SessionsPageView().appBackground()
        } else {
            HealthWorkoutView().appBackground()
        }
    }
}

struct DashboardEditView: View {
    @EnvironmentObject var dashboardService: DashboardService
    @Binding var isPresented: Bool
    @State private var draftModules: [DashboardModule] = []
    @State private var showAddModule = false
    @State private var selectedModuleSelection: ModuleSelection?
    @State private var dragState: DragState?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Button(action: {
                    showAddModule = true
                }) {
                    Label("Add Module", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(draftModules) { module in
                            DashboardEditorRow(
                                module: module,
                                isDragging: dragState?.moduleID == module.id,
                                dragOffset: dragOffset(for: module.id),
                                onOpenSettings: {
                                    selectedModuleSelection = ModuleSelection(id: module.id)
                                },
                                onDragChanged: { value in
                                    updateDrag(for: module.id, translation: value.translation.height)
                                },
                                onDragEnded: { _ in
                                    finishDrag()
                                }
                            )
                            .padding(.horizontal, 16)
                            .zIndex(dragState?.moduleID == module.id ? 1 : 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        resetDraftModules()
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveDraftModules()
                    }
                }
            }
            .onAppear {
                loadDraftModules()
            }
            .sheet(isPresented: $showAddModule) {
                DashboardAddModuleSheet(isPresented: $showAddModule, modules: $draftModules)
            }
            .sheet(item: $selectedModuleSelection) { selection in
                if let selectedIndex = draftModules.firstIndex(where: { $0.id == selection.id }) {
                    DashboardModuleSettingsSheet(module: $draftModules[selectedIndex])
                }
            }
        }
    }

    private func reindexDraftModules() {
        for index in draftModules.indices {
            draftModules[index].order = index
        }
    }

    private func loadDraftModules() {
        draftModules = dashboardService.modulesSnapshotForEditor()
        dragState = nil
    }

    private func resetDraftModules() {
        draftModules = dashboardService.defaultModulesForEditor()
        reindexDraftModules()
        dragState = nil
    }

    private func saveDraftModules() {
        reindexDraftModules()
        dashboardService.applyEditorModules(draftModules)
        isPresented = false
    }

    private func dragOffset(for moduleID: String) -> CGFloat {
        guard let dragState, dragState.moduleID == moduleID else { return 0 }
        return dragState.displayOffset
    }

    private func updateDrag(for moduleID: String, translation: CGFloat) {
        guard let moduleIndex = draftModules.firstIndex(where: { $0.id == moduleID }) else { return }

        if dragState == nil {
            dragState = DragState(
                moduleID: moduleID,
                startIndex: moduleIndex,
                currentIndex: moduleIndex,
                displayOffset: 0
            )
        }

        guard var dragState, dragState.moduleID == moduleID else { return }

        let rawShift = Int((translation / rowStep).rounded())
        let targetIndex = max(0, min(draftModules.count - 1, dragState.startIndex + rawShift))

        if targetIndex != dragState.currentIndex {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.84)) {
                let movingModule = draftModules.remove(at: dragState.currentIndex)
                draftModules.insert(movingModule, at: targetIndex)
            }
            dragState.currentIndex = targetIndex
        }

        let rowShift = CGFloat(dragState.currentIndex - dragState.startIndex) * rowStep
        dragState.displayOffset = translation - rowShift
        self.dragState = dragState
    }

    private func finishDrag() {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.84)) {
            dragState = nil
        }
        reindexDraftModules()
    }

    private var rowStep: CGFloat { 92 }

    private struct ModuleSelection: Identifiable {
        let id: String
    }

    private struct DragState {
        let moduleID: String
        let startIndex: Int
        var currentIndex: Int
        var displayOffset: CGFloat
    }
}

struct DashboardEditorRow: View {
    let module: DashboardModule
    let isDragging: Bool
    let dragOffset: CGFloat
    let onOpenSettings: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.type.iconName)
                .foregroundColor(.secondary)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text(module.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text(module.size.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(module.isVisible ? "Visible" : "Hidden")
                        .font(.caption)
                        .foregroundColor(module.isVisible ? .green : .secondary)
                }
            }

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged(onDragChanged)
                        .onEnded(onDragEnded)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: isDragging ? Color.black.opacity(0.12) : Color.clear, radius: 10, y: 4)
        .scaleEffect(isDragging ? 1.02 : 1)
        .offset(y: dragOffset)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.84), value: dragOffset)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Use the reorder handle to move this module")
    }
}

struct DashboardModuleSettingsSheet: View {
    @Binding var module: DashboardModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: module.type.iconName)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.type.displayName)
                                .font(.headline)
                            Text(module.id)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section("Visibility") {
                    Toggle("Visible", isOn: $module.isVisible)
                }

                Section("Size") {
                    Picker("Module Size", selection: $module.size) {
                        ForEach(module.type.allowedSizes, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Module Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if !module.type.allowedSizes.contains(module.size) {
                            module.size = module.type.allowedSizes.first ?? .small
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DashboardAddModuleSheet: View {
    @Binding var isPresented: Bool
    @Binding var modules: [DashboardModule]

    var body: some View {
        NavigationStack {
            List {
                Section("Small (1x1)") {
                    ForEach(ModuleType.allCases, id: \.self) { type in
                        if type.allowedSizes.contains(.small) {
                            addButton(for: type, size: .small)
                        }
                    }
                }

                Section("Medium (2x1)") {
                    ForEach(ModuleType.allCases, id: \.self) { type in
                        if type.allowedSizes.contains(.medium) {
                            addButton(for: type, size: .medium)
                        }
                    }
                }

                Section("Large (2x2)") {
                    ForEach(ModuleType.allCases, id: \.self) { type in
                        if type.allowedSizes.contains(.large) {
                            addButton(for: type, size: .large)
                        }
                    }
                }
            }
            .navigationTitle("Add Module")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func addButton(for type: ModuleType, size: ModuleSize) -> some View {
        Button(action: {
            addOrEnable(type: type, size: size)
            isPresented = false
        }) {
            HStack {
                Label(type.displayName, systemImage: type.iconName)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .foregroundColor(.primary)
    }

    private func addOrEnable(type: ModuleType, size: ModuleSize) {
        let nextOrder = (modules.map(\.order).max() ?? -1) + 1
        let normalizedSize = type.allowedSizes.contains(size) ? size : (type.allowedSizes.first ?? .small)

        modules.append(
            DashboardModule(
                type: type,
                size: normalizedSize,
                order: nextOrder,
                isVisible: true
            )
        )

        modules = modules
            .sorted(by: { $0.order < $1.order })
            .enumerated()
            .map { index, module in
                var updated = module
                updated.order = index
                return updated
            }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .modelContainer(for: Routine.self, inMemory: true)
            .modelContainer(for: Exercise.self, inMemory: true)
    }
}
