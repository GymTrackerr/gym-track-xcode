import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var hkManager: HealthKitManager
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    @State private var openedSession: Session? = nil
    @State private var navigateToSession: Bool = false
    @State private var showEditMenu: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let _ = userService.currentUser {
                if !navigateToSession {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            if (userService.currentUser?.allowHealthAccess ?? false) {
                                DashboardGridView(
                                    openedSession: $openedSession
                                )
                            } else {
                                VStack(spacing: 16) {
                                    Text("Health Data Not Available")
                                        .font(.headline)
                                    Text("Please enable HealthKit access in Settings to see your dashboard")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            } else {
                Text("Please continue to onboarding")
            }
        }
        .task {
            await hkManager.requestAuthorization()
            await hkManager.fetchUserWeight()
            await hkManager.fetchWorkouts()
            await hkManager.fetchActivityRingStatus()
            guard let userId = userService.currentUser?.id.uuidString else { return }
            await healthKitDailyStore.refreshTodayIfNeeded(userId: userId)
            _ = try? await healthKitDailyStore.dailySummaries(
                endingOn: Date(),
                days: 7,
                userId: userId,
                policy: .refreshIfStale
            )
        }
        .navigationDestination(isPresented: $navigateToSession) {
            Group {
                if let openedSession {
                    SingleSessionView(session: openedSession)
                } else {
                    EmptyView()
                }
            }
        }
        .navigationTitle(userService.currentUser != nil ? "Welcome \(userService.currentUser!.name)" : "Home" )
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
    @Binding var openedSession: Session?
    
    var visibleModules: [DashboardModule] {
        dashboardService.getVisibleModules()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Dashboard Modules
            if visibleModules.isEmpty {
                EmptyDashboardView()
                    .padding()
            } else {
                DashboardModulesView(
                    visibleModules: visibleModules
                )
                .padding()
            }
            
            // Sessions Section
            VStack(alignment: .leading) {
                Text("Sessions")
                    .font(.headline)
                
                SessionsView(openedSession: $openedSession)
                    .onChange(of: openedSession) {
                        if openedSession != nil {
                            // Handle navigation
                        }
                    }
            }
            .padding(.horizontal)
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
        VStack(spacing: 12) {
            ForEach(buildModuleRows().indices, id: \.self) { rowIndex in
                let row = buildModuleRows()[rowIndex]
                
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
        NavigationLink(destination: FitSightView().appBackground()) {
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
        guard let userId = userService.currentUser?.id.uuidString else {
            deficitSurplus = nil
            return
        }
        deficitSurplus = try? await healthMetricsService.deficitSurplus(for: Date(), userId: userId)
    }
}

struct CurrentWeightModuleView: View {
    @EnvironmentObject var hkManager: HealthKitManager
    
    var body: some View {
        MetricCard(
            title: "Current Weight",
            value: String(format: "%.1f", hkManager.userWeight ?? 0.00),
            icon: "lock.fill",
            hasBackground: false
        )
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
    @EnvironmentObject var hkManager: HealthKitManager
    
    var body: some View {
        if let ars = hkManager.activityRingStatus {
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
    
    var body: some View {
        NavigationLink(destination: HealthWorkoutView().appBackground()) {
            MetricCard(
                title: "Fitness Workouts",
                value: String(hkManager.workouts.count),
                icon: "figure.strengthtraining.traditional",
                pageNav: true,
                hasBackground: false
            )
        }
    }
}

struct DashboardEditView: View {
    @EnvironmentObject var dashboardService: DashboardService
    @Binding var isPresented: Bool
    @EnvironmentObject var hkManager: HealthKitManager
    
    @State private var showAddModule = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Add Module Button
                Button(action: { showAddModule = true }) {
                    Label("Add Module", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                .padding()
                
                // Editor Grid View
                if dashboardService.modules.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName:"square.grid.2x2")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No modules configured")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(dashboardService.modules, id: \.id) { module in
                            ModuleEditCard(
                                module: module
                            )
                        }
                        .onMove { indices, newOffset in
                            dashboardService.reorderModules(indices, with: newOffset)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                }
                
                Spacer()
                
                // Reset Button
                Button(action: {
                    dashboardService.resetToDefaults()
                }) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.red)
                }
                .padding()
            }
            .navigationTitle("Edit Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showAddModule) {
                AddModuleSheet(isPresented: $showAddModule)
            }
        }
    }
}

struct ModuleEditCard: View {
    let module: DashboardModule
    @EnvironmentObject var dashboardService: DashboardService
    
    @State private var selectedSize: ModuleSize
    
    init(module: DashboardModule) {
        self.module = module
        _selectedSize = State(initialValue: module.size)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with icon, title and delete button
            HStack(spacing: 8) {
                Image(systemName: module.type.iconName)
                    .foregroundColor(.secondary)
                    .font(.body)
                
                Text(module.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    dashboardService.removeModule(module.id)
                }) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Size selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                Picker("Module Size", selection: $selectedSize) {
                    ForEach(module.type.allowedSizes, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .onChange(of: selectedSize) {
                    dashboardService.updateModuleSize(module.id, newSize: selectedSize)
                }
            }
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground).opacity(0.5))
        .cornerRadius(10)
        .border(Color.gray.opacity(0.2), width: 1)
    }
}

struct AddModuleSheet: View {
    @EnvironmentObject var dashboardService: DashboardService
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List {
                Section("Small (1x1)") {
                    ForEach(ModuleType.allCases, id: \.self) { type in
                        if type.allowedSizes.contains(.small) {
                            Button(action: {
                                dashboardService.addModule(type, size: .small)
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
                    }
                }
                
                Section("Medium (2x1)") {
                    ForEach(ModuleType.allCases, id: \.self) { type in
                        if type.allowedSizes.contains(.medium) {
                            Button(action: {
                                dashboardService.addModule(type, size: .medium)
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
                    }
                }
                
                Section("Large (2x2)") {
                    ForEach(ModuleType.allCases, id: \.self) { type in
                        if type.allowedSizes.contains(.large) {
                            Button(action: {
                                dashboardService.addModule(type, size: .large)
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
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Add Module")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
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
