import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var hkManager: HealthKitManager
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @EnvironmentObject var dashboardService: DashboardService

    @State private var openedSession: Session? = nil
    
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
                    Button(action: {
                        dashboardService.isEditingMode.toggle()
                    }) {
                        Label(
                            dashboardService.isEditingMode ? "Done" : "Edit",
                            systemImage: dashboardService.isEditingMode ? "checkmark.circle" : "pencil"
                        )
                    }
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }
}

struct DashboardGridView: View {
    @EnvironmentObject var dashboardService: DashboardService
    @EnvironmentObject var userService: UserService
    @Binding var openedSession: Session?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if userService.currentUser?.allowHealthAccess ?? false {
                DashboardModulesView()
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
    @EnvironmentObject var dashboardService: DashboardService
    @State private var selectedModuleID: String?
    @State private var showAddModuleSheet = false
    @State private var availableWidth: CGFloat = 0
    @State private var draftModules: [DashboardModule] = []
    @State private var draggedModuleID: String?

    var body: some View {
        let effectiveWidth = max(availableWidth, UIScreen.main.bounds.width - 32)
        let columnCount = dashboardService.defaultColumnCount(for: effectiveWidth)
        let liveModules = dashboardService.getVisibleModules(columns: columnCount)
        let displayModules = dashboardService.isEditingMode ? draftModules : liveModules
        let selectedModule = displayModules.first(where: { $0.id == selectedModuleID })
        let columnWidth = dashboardColumnWidth(for: effectiveWidth, columns: columnCount)
        let rows = dashboardRows(for: displayModules, columnCount: columnCount)

        VStack(alignment: .leading, spacing: 16) {
            if dashboardService.isEditingMode {
                DashboardInlineEditorBar(
                    selectedModule: selectedModule,
                    onAddModule: { showAddModuleSheet = true },
                    onApplyPreset: { preset in
                        draftModules = dashboardService.modulesForPreset(preset)
                        selectedModuleID = draftModules.first?.id
                    }
                )
            }

            if displayModules.isEmpty {
                EmptyDashboardView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        switch row {
                        case let .compact(modules):
                            LazyVGrid(columns: gridColumns(count: columnCount), spacing: 12) {
                                ForEach(modules) { module in
                                    dashboardCard(for: module, columnWidth: columnWidth)
                                }
                            }
                        case let .expanded(module):
                            dashboardCard(for: module, columnWidth: columnWidth)
                        }
                    }
                }
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.86),
                    value: displayModules.map { "\($0.id)-\($0.order)-\($0.size.rawValue)-\($0.isVisible)" }
                )
            }

            if dashboardService.isEditingMode {
                DashboardSelectedModuleControls(
                    module: selectedModule,
                    onSizeChange: { newSize in
                        updateSelectedModule { module in
                            let allowedSizes = module.type.allowedSizes
                            module.size = allowedSizes.contains(newSize) ? newSize : (allowedSizes.first ?? .small)
                        }
                    },
                    onToggleVisibility: { isVisible in
                        if !isVisible {
                            hideSelectedModule()
                        }
                    }
                )
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        availableWidth = newWidth
                    }
            }
        )
        .sheet(isPresented: $showAddModuleSheet) {
            DashboardInlineAddModuleSheet(isPresented: $showAddModuleSheet) { type, size in
                addDraftModule(type: type, size: size)
            }
        }
        .onAppear {
            if dashboardService.isEditingMode {
                beginEditing(with: liveModules)
            }
        }
        .onChange(of: dashboardService.isEditingMode) { _, isEditing in
            if isEditing {
                beginEditing(with: liveModules)
            } else {
                finishEditing()
            }
        }
        .onChange(of: liveModules.map(\.id)) { _, ids in
            guard !dashboardService.isEditingMode else { return }
            if let selectedModuleID, !ids.contains(selectedModuleID) {
                self.selectedModuleID = ids.first
            }
        }
    }

    private func gridColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: max(count, 2))
    }

    private func dashboardColumnWidth(for width: CGFloat, columns: Int) -> CGFloat {
        let safeColumns = max(columns, 2)
        let totalSpacing = CGFloat(safeColumns - 1) * 12
        return max((width - totalSpacing) / CGFloat(safeColumns), 120)
    }

    private func dashboardRows(for modules: [DashboardModule], columnCount: Int) -> [DashboardRenderRow] {
        let safeColumnCount = max(columnCount, 2)
        var rows: [DashboardRenderRow] = []
        var compactModules: [DashboardModule] = []

        for module in modules {
            if module.size == .small {
                compactModules.append(module)
                if compactModules.count == safeColumnCount {
                    rows.append(.compact(compactModules))
                    compactModules.removeAll()
                }
            } else {
                if !compactModules.isEmpty {
                    rows.append(.compact(compactModules))
                    compactModules.removeAll()
                }
                rows.append(.expanded(module))
            }
        }

        if !compactModules.isEmpty {
            rows.append(.compact(compactModules))
        }

        return rows
    }

    private func dashboardCardHeight(for module: DashboardModule, columnWidth: CGFloat) -> CGFloat {
        let baseHeight = max(min(columnWidth * 0.92, 220), 124)
        switch module.size {
        case .small:
            return baseHeight
        case .medium:
            return baseHeight * 1.18
        case .large:
            return baseHeight * 1.5
        }
    }

    @ViewBuilder
    private func dashboardCard(for module: DashboardModule, columnWidth: CGFloat) -> some View {
        if dashboardService.isEditingMode {
            DashboardEditableModuleCard(
                module: module,
                isSelected: selectedModuleID == module.id,
                height: dashboardCardHeight(for: module, columnWidth: columnWidth),
                onSelect: {
                    selectedModuleID = module.id
                }
            )
            .frame(maxWidth: module.size == .small ? nil : .infinity)
            .onDrag {
                draggedModuleID = module.id
                selectedModuleID = module.id
                return NSItemProvider(object: module.id as NSString)
            } preview: {
                DashboardModuleDragPreview(module: module)
            }
            .onDrop(
                of: [UTType.text],
                delegate: DashboardModuleDropDelegate(
                    targetModuleID: module.id,
                    modules: $draftModules,
                    draggedModuleID: $draggedModuleID,
                    selectedModuleID: $selectedModuleID
                )
            )
        } else {
            ModuleDisplayView(module: module)
                .frame(
                    maxWidth: module.size == .small ? nil : .infinity,
                    minHeight: dashboardCardHeight(for: module, columnWidth: columnWidth),
                    maxHeight: dashboardCardHeight(for: module, columnWidth: columnWidth)
                )
        }
    }

    private func beginEditing(with modules: [DashboardModule]) {
        draftModules = modules.enumerated().map { index, module in
            var updated = module
            updated.order = index
            return updated
        }
        if let selectedModuleID, draftModules.contains(where: { $0.id == selectedModuleID }) {
            return
        }
        selectedModuleID = draftModules.first?.id
    }

    private func finishEditing() {
        guard !draftModules.isEmpty else {
            dashboardService.applyEditorModules([])
            selectedModuleID = nil
            draggedModuleID = nil
            return
        }

        dashboardService.applyEditorModules(draftModules)
        if let selectedModuleID,
           !draftModules.contains(where: { $0.id == selectedModuleID }) {
            self.selectedModuleID = draftModules.first?.id
        }
        draggedModuleID = nil
    }

    private func addDraftModule(type: ModuleType, size: ModuleSize) {
        let allowedSizes = type.allowedSizes
        let normalizedSize = allowedSizes.contains(size) ? size : (allowedSizes.first ?? .small)
        draftModules.append(
            DashboardModule(
                type: type,
                size: normalizedSize,
                order: draftModules.count,
                isVisible: true
            )
        )
        draftModules = reindexedDraftModules(draftModules)
        selectedModuleID = draftModules.last?.id
    }

    private func updateSelectedModule(_ update: (inout DashboardModule) -> Void) {
        guard let selectedModuleID,
              let index = draftModules.firstIndex(where: { $0.id == selectedModuleID }) else {
            return
        }

        update(&draftModules[index])
        draftModules = reindexedDraftModules(draftModules)
    }

    private func hideSelectedModule() {
        guard let selectedModuleID else { return }
        draftModules.removeAll { $0.id == selectedModuleID }
        draftModules = reindexedDraftModules(draftModules)
        self.selectedModuleID = draftModules.first?.id
    }

    private func reindexedDraftModules(_ modules: [DashboardModule]) -> [DashboardModule] {
        modules.enumerated().map { index, module in
            var updated = module
            updated.order = index
            updated.isVisible = true
            return updated
        }
    }
}

enum DashboardRenderRow {
    case compact([DashboardModule])
    case expanded(DashboardModule)
}

struct DashboardInlineEditorBar: View {
    let selectedModule: DashboardModule?
    let onAddModule: () -> Void
    let onApplyPreset: (DashboardPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onAddModule) {
                    Label("Add Module", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    ForEach(DashboardPreset.allCases) { preset in
                        Button {
                            onApplyPreset(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                Text(preset.description)
                            }
                        }
                    }
                } label: {
                    Label("Presets", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text(selectedModule == nil ? "Drag a card onto another card to reorder it, or tap one to edit its size." : "The selected card can be resized or hidden below while the grid stays live.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardSelectedModuleControls: View {
    let module: DashboardModule?
    let onSizeChange: (ModuleSize) -> Void
    let onToggleVisibility: (Bool) -> Void

    var body: some View {
        Group {
            if let module {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: module.type.iconName)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.type.displayName)
                                .font(.headline)
                            Text("Module ID: \(module.id)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            onToggleVisibility(false)
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Size")
                            .font(.subheadline.weight(.semibold))

                        Picker(
                            "Module Size",
                            selection: Binding(
                                get: { module.size },
                                set: { onSizeChange($0) }
                            )
                        ) {
                            ForEach(module.type.allowedSizes, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("Select a module to resize it or hide it.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct DashboardInlineAddModuleSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (ModuleType, ModuleSize) -> Void

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
        Button {
            onAdd(type, size)
            isPresented = false
        } label: {
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

struct DashboardEditableModuleCard: View {
    let module: DashboardModule
    let isSelected: Bool
    let height: CGFloat
    let onSelect: () -> Void

    var body: some View {
        ModuleDisplayView(
            module: module,
            isEditing: true,
            isSelected: isSelected,
            onSelect: onSelect
        )
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            Text(module.size.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
    }
}

struct DashboardModuleDragPreview: View {
    let module: DashboardModule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.type.iconName)
                .font(.body.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.type.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(module.size.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 200, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardModuleDropDelegate: DropDelegate {
    let targetModuleID: String
    @Binding var modules: [DashboardModule]
    @Binding var draggedModuleID: String?
    @Binding var selectedModuleID: String?

    func dropEntered(info: DropInfo) {
        guard let draggedModuleID,
              draggedModuleID != targetModuleID,
              let fromIndex = modules.firstIndex(where: { $0.id == draggedModuleID }),
              let toIndex = modules.firstIndex(where: { $0.id == targetModuleID }) else {
            return
        }

        var reordered = modules
        let movedModule = reordered.remove(at: fromIndex)
        reordered.insert(movedModule, at: toIndex)
        modules = reindexed(reordered)
        selectedModuleID = draggedModuleID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModuleID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        selectedModuleID = draggedModuleID ?? selectedModuleID
    }

    private func reindexed(_ modules: [DashboardModule]) -> [DashboardModule] {
        modules.enumerated().map { index, module in
            var updated = module
            updated.order = index
            updated.isVisible = true
            return updated
        }
    }
}

struct ModuleDisplayView: View {
    let module: DashboardModule
    var isEditing: Bool = false
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    
    var body: some View {
        DashboardModuleCardChrome(module: module, isEditing: isEditing, isSelected: isSelected, onSelect: onSelect) {
            DashboardModuleContent(module: module)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DashboardModuleVisualSpec(module.size).contentPadding)
        }
    }
}

struct DashboardModuleCardChrome<Content: View>: View {
    let module: DashboardModule
    let isEditing: Bool
    let isSelected: Bool
    let onSelect: (() -> Void)?
    let content: Content

    init(
        module: DashboardModule,
        isEditing: Bool,
        isSelected: Bool,
        onSelect: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) {
        self.module = module
        self.isEditing = isEditing
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.content = content()
    }

    var body: some View {
        let spec = DashboardModuleVisualSpec(module.size)

        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: module.type.iconName)
                        .foregroundColor(.secondary)
                        .font(.body)

                    Text(module.type.displayName)
                        .font(spec.headerFont)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(spec.headerPadding)

                Divider()

                content
            }
            .allowsHitTesting(!isEditing)
            .glassEffect(in: .rect(cornerRadius: 12.0))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isEditing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.black.opacity(0.02))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        onSelect?()
                    }

                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.35), lineWidth: isSelected ? 3 : 1.25)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct DashboardModuleVisualSpec {
    let headerPadding: CGFloat
    let contentPadding: CGFloat
    let headerFont: Font

    init(_ size: ModuleSize) {
        switch size {
        case .small:
            headerPadding = 8
            contentPadding = 8
            headerFont = .caption
        case .medium:
            headerPadding = 10
            contentPadding = 10
            headerFont = .caption
        case .large:
            headerPadding = 12
            contentPadding = 12
            headerFont = .subheadline
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

#Preview {
    NavigationStack {
        HomeView()
            .modelContainer(for: Routine.self, inMemory: true)
            .modelContainer(for: Exercise.self, inMemory: true)
    }
}
