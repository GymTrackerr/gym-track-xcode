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
                .refreshable {
                    await refreshHealthData(forceRefresh: true)
                }
            } else {
                Text("Please continue to onboarding")
            }
        }
        .task(id: userService.currentUser?.id) {
            await refreshHealthData(requestAuthorization: true)
        }
        .navigationTitle(userService.currentUser.map { "Welcome \($0.name)" } ?? "Home")
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

    private func refreshHealthData(
        forceRefresh: Bool = false,
        requestAuthorization: Bool = false
    ) async {
        guard let currentUser = userService.currentUser, currentUser.isDemo != true else { return }
        guard currentUser.allowHealthAccess else { return }

        if requestAuthorization {
            await hkManager.requestAuthorization()
        }

        await hkManager.fetchWorkouts()
        let userId = currentUser.id.uuidString

        if forceRefresh {
            await healthKitDailyStore.forceRefreshRecentData(userId: userId)
        } else {
            await healthKitDailyStore.refreshTodayIfNeeded(userId: userId)
            _ = try? await healthKitDailyStore.dailySummaries(
                endingOn: Date(),
                days: 7,
                userId: userId,
                policy: .refreshIfStale
            )
        }
    }
}

struct DashboardGridView: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore
    @Binding var openedSession: Session?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if exerciseService.showExistingUserCatalogPrompt {
                ExerciseCatalogPromptBanner(
                    onEnable: { exerciseService.acceptExistingUserCatalogPromptAndSync() },
                    onDismiss: { exerciseService.dismissExistingUserCatalogPrompt() }
                )
            }

            if exerciseService.isCatalogSyncInFlight {
                ExerciseCatalogSyncProgressCard()
            }

            if healthKitDailyStore.isBackfillingHistory {
                HealthBackfillProgressCard()
            }

            if userService.currentUser?.allowHealthAccess != true && userService.currentUser?.isDemo != true {
                HealthAccessBanner()
            }

            DashboardModulesView()

            VStack(alignment: .leading, spacing: 12) {
                Text("Sessions")
                    .font(.headline)

                SessionsView(openedSession: $openedSession)
            }
        }
    }
}

struct ExerciseCatalogPromptBanner: View {
    let onEnable: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download ExerciseDB?")
                .font(.headline)
            Text("Enable optional ExerciseDB sync for faster exercise browsing and cached thumbnails.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Enable Sync", action: onEnable)
                    .buttonStyle(.borderedProminent)
                Button("Not Now", action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ExerciseCatalogSyncProgressCard: View {
    @EnvironmentObject var exerciseService: ExerciseService

    private var progress: Double {
        guard exerciseService.catalogSyncProgressTotal > 0 else { return 0 }
        return min(
            max(
                Double(exerciseService.catalogSyncProgressCompleted) /
                Double(exerciseService.catalogSyncProgressTotal),
                0
            ),
            1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ExerciseDB Sync")
                .font(.headline)
            ProgressView(value: progress)
            Text(exerciseService.catalogSyncStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct HealthBackfillProgressCard: View {
    @EnvironmentObject var healthKitDailyStore: HealthKitDailyStore

    private var progress: Double {
        guard healthKitDailyStore.backfillProgressTotal > 0 else { return 0 }
        return min(
            max(
                Double(healthKitDailyStore.backfillProgressCompleted) /
                Double(healthKitDailyStore.backfillProgressTotal),
                0
            ),
            1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health History Backfill")
                .font(.headline)
            ProgressView(value: progress)
            Text(healthKitDailyStore.backfillStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct HealthAccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect Apple Health")
                .font(.headline)
            Text("Health-backed cards like weight, steps, sleep, activity rings, and imported workouts will stay visible here once access is enabled in Settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
            Text("Tap Edit to add modules or apply a preset")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

struct DashboardModulesView: View {
    @EnvironmentObject var dashboardService: DashboardService
    @State private var showAddModuleSheet = false
    @State private var availableWidth: CGFloat = 0
    @State private var draftModules: [DashboardModule] = []
    @State private var draggedModuleID: String?

    private let dashboardSpacing: CGFloat = 12

    var body: some View {
        let effectiveWidth = max(availableWidth, UIScreen.main.bounds.width - 32)
        let columnCount = dashboardService.defaultColumnCount(for: effectiveWidth)
        let liveModules = dashboardService.visibleModules
        let displayModules = dashboardService.isEditingMode ? draftModules : liveModules
        let layout = DashboardGridLayout(
            modules: displayModules,
            availableWidth: effectiveWidth,
            columnCount: columnCount,
            spacing: dashboardSpacing
        )
        let existingTypes = Set(displayModules.map(\.type))

        VStack(alignment: .leading, spacing: 16) {
            if dashboardService.isEditingMode {
                DashboardInlineEditorBar(
                    canAddModules: existingTypes.count < ModuleType.allCases.count,
                    onAddModule: { showAddModuleSheet = true },
                    onApplyPreset: { preset in
                        draftModules = dashboardService.modulesForPreset(preset)
                    }
                )
            }

            if displayModules.isEmpty {
                EmptyDashboardView()
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.items) { item in
                        dashboardCard(for: item)
                            .offset(x: item.origin.x, y: item.origin.y)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: layout.height, alignment: .topLeading)
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.86),
                    value: displayModules.map { "\($0.id)-\($0.order)-\($0.size.rawValue)-\($0.isVisible)" }
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
            DashboardInlineAddModuleSheet(
                isPresented: $showAddModuleSheet,
                existingTypes: existingTypes
            ) { type, size in
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
    }

    @ViewBuilder
    private func dashboardCard(for item: DashboardGridLayoutItem) -> some View {
        if dashboardService.isEditingMode {
            DashboardEditableModuleCard(
                module: item.module,
                isDragging: draggedModuleID == item.module.id,
                width: item.size.width,
                height: item.size.height,
                onSizeChange: { newSize in
                    updateDraftModule(moduleID: item.module.id) { draftModule in
                        let allowedSizes = draftModule.type.allowedSizes
                        draftModule.size = allowedSizes.contains(newSize) ? newSize : (allowedSizes.first ?? .small)
                    }
                },
                onHide: {
                    hideDraftModule(moduleID: item.module.id)
                }
            )
            .onDrag {
                draggedModuleID = item.module.id
                return NSItemProvider(object: item.module.id as NSString)
            } preview: {
                DashboardModuleDragPreview(module: item.module)
            }
            .onDrop(
                of: [UTType.text],
                delegate: DashboardModuleDropDelegate(
                    targetModuleID: item.module.id,
                    modules: $draftModules,
                    draggedModuleID: $draggedModuleID
                )
            )
        } else {
            ModuleDisplayView(module: item.module)
                .frame(width: item.size.width, height: item.size.height)
        }
    }

    private func beginEditing(with modules: [DashboardModule]) {
        draftModules = reindexedDraftModules(modules)
    }

    private func finishEditing() {
        dashboardService.saveVisibleModules(draftModules)
        draggedModuleID = nil
    }

    private func addDraftModule(type: ModuleType, size: ModuleSize) {
        guard !draftModules.contains(where: { $0.type == type }) else { return }
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
    }

    private func updateDraftModule(moduleID: String, update: (inout DashboardModule) -> Void) {
        guard let index = draftModules.firstIndex(where: { $0.id == moduleID }) else { return }
        update(&draftModules[index])
        draftModules = reindexedDraftModules(draftModules)
    }

    private func hideDraftModule(moduleID: String) {
        draftModules.removeAll { $0.id == moduleID }
        draftModules = reindexedDraftModules(draftModules)
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

struct DashboardGridLayoutItem: Identifiable {
    let module: DashboardModule
    let origin: CGPoint
    let size: CGSize
    let row: Int
    let column: Int

    var id: String { module.id }
}

struct DashboardGridLayout {
    let items: [DashboardGridLayoutItem]
    let height: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let spacing: CGFloat

    init(
        modules: [DashboardModule],
        availableWidth: CGFloat,
        columnCount: Int,
        spacing: CGFloat
    ) {
        let safeColumnCount = max(columnCount, 2)
        let totalSpacing = CGFloat(safeColumnCount - 1) * spacing
        let cellWidth = max((availableWidth - totalSpacing) / CGFloat(safeColumnCount), 120)
        let cellHeight = max(min(cellWidth * 0.92, 220), 124)

        var occupancy: [[Bool]] = []
        var layoutItems: [DashboardGridLayoutItem] = []
        var maxOccupiedRow = 0

        func ensureRows(_ rowCount: Int) {
            while occupancy.count < rowCount {
                occupancy.append(Array(repeating: false, count: safeColumnCount))
            }
        }

        func canPlace(row: Int, column: Int, columnSpan: Int, rowSpan: Int) -> Bool {
            guard column + columnSpan <= safeColumnCount else { return false }
            ensureRows(row + rowSpan)

            for rowIndex in row..<(row + rowSpan) {
                for columnIndex in column..<(column + columnSpan) {
                    if occupancy[rowIndex][columnIndex] {
                        return false
                    }
                }
            }

            return true
        }

        func markOccupied(row: Int, column: Int, columnSpan: Int, rowSpan: Int) {
            for rowIndex in row..<(row + rowSpan) {
                for columnIndex in column..<(column + columnSpan) {
                    occupancy[rowIndex][columnIndex] = true
                }
            }
        }

        for module in modules {
            let columnSpan = min(module.size.columnSpan, safeColumnCount)
            let rowSpan = module.size.rowSpan
            var targetRow = 0
            var targetColumn = 0
            var placed = false

            while !placed {
                ensureRows(targetRow + rowSpan)

                for candidateColumn in 0...(safeColumnCount - columnSpan) {
                    if canPlace(
                        row: targetRow,
                        column: candidateColumn,
                        columnSpan: columnSpan,
                        rowSpan: rowSpan
                    ) {
                        targetColumn = candidateColumn
                        placed = true
                        break
                    }
                }

                if !placed {
                    targetRow += 1
                }
            }

            markOccupied(row: targetRow, column: targetColumn, columnSpan: columnSpan, rowSpan: rowSpan)

            let itemWidth = (CGFloat(columnSpan) * cellWidth) + (CGFloat(columnSpan - 1) * spacing)
            let itemHeight = (CGFloat(rowSpan) * cellHeight) + (CGFloat(rowSpan - 1) * spacing)
            let origin = CGPoint(
                x: CGFloat(targetColumn) * (cellWidth + spacing),
                y: CGFloat(targetRow) * (cellHeight + spacing)
            )

            layoutItems.append(
                DashboardGridLayoutItem(
                    module: module,
                    origin: origin,
                    size: CGSize(width: itemWidth, height: itemHeight),
                    row: targetRow,
                    column: targetColumn
                )
            )
            maxOccupiedRow = max(maxOccupiedRow, targetRow + rowSpan)
        }

        self.items = layoutItems
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.spacing = spacing
        self.height = maxOccupiedRow > 0
            ? (CGFloat(maxOccupiedRow) * cellHeight) + (CGFloat(maxOccupiedRow - 1) * spacing)
            : 0
    }
}

struct DashboardInlineEditorBar: View {
    let canAddModules: Bool
    let onAddModule: () -> Void
    let onApplyPreset: (DashboardPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onAddModule) {
                    Label("Add Module", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAddModules)

                Menu {
                    Section("Presets") {
                        ForEach(DashboardPreset.productionCases) { preset in
                            Button {
                                onApplyPreset(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName)
                                    Text(preset.description)
                                }
                            }
                        }
                    }

#if DEBUG
                    Section("Debug Layout Tests") {
                        ForEach(DashboardPreset.debugCases) { preset in
                            Button {
                                onApplyPreset(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName)
                                    Text(preset.description)
                                }
                            }
                        }
                    }
#endif
                } label: {
                    Label("Presets", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text("Drag cards to reorder them, and use the menu on each card to resize or hide it.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardInlineAddModuleSheet: View {
    @Binding var isPresented: Bool
    let existingTypes: Set<ModuleType>
    let onAdd: (ModuleType, ModuleSize) -> Void

    var body: some View {
        NavigationStack {
            List {
                if availableTypes.isEmpty {
                    Text("All module types are already on your dashboard.")
                        .foregroundColor(.secondary)
                } else {
                    if !smallTypes.isEmpty {
                        Section("Small (1x1)") {
                            ForEach(smallTypes, id: \.self) { type in
                                addButton(for: type, size: .small)
                            }
                        }
                    }

                    if !mediumTypes.isEmpty {
                        Section("Medium (2x1)") {
                            ForEach(mediumTypes, id: \.self) { type in
                                addButton(for: type, size: .medium)
                            }
                        }
                    }

                    if !largeTypes.isEmpty {
                        Section("Large (2x2)") {
                            ForEach(largeTypes, id: \.self) { type in
                                addButton(for: type, size: .large)
                            }
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

    private var availableTypes: [ModuleType] {
        ModuleType.allCases.filter { !existingTypes.contains($0) }
    }

    private var smallTypes: [ModuleType] {
        availableTypes.filter { $0.allowedSizes.contains(.small) }
    }

    private var mediumTypes: [ModuleType] {
        availableTypes.filter { $0.allowedSizes.contains(.medium) }
    }

    private var largeTypes: [ModuleType] {
        availableTypes.filter { $0.allowedSizes.contains(.large) }
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
    let isDragging: Bool
    let width: CGFloat
    let height: CGFloat
    let onSizeChange: (ModuleSize) -> Void
    let onHide: () -> Void

    var body: some View {
        ModuleDisplayView(
            module: module,
            isEditing: true,
            headerAccessory: AnyView(moduleActionMenu)
        )
        .frame(width: width, height: height)
        .scaleEffect(isDragging ? 0.97 : 1)
        .opacity(isDragging ? 0.68 : 1)
        .shadow(
            color: isDragging ? Color.black.opacity(0.16) : Color.clear,
            radius: isDragging ? 16 : 0,
            y: isDragging ? 8 : 0
        )
        .animation(.easeInOut(duration: 0.18), value: isDragging)
        .overlay(alignment: .bottomLeading) {
            Text(module.size.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "hand.draw")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(10)
        }
    }

    private var moduleActionMenu: some View {
        Menu {
            if module.type.allowedSizes.count > 1 {
                Section("Size") {
                    ForEach(module.type.allowedSizes, id: \.self) { size in
                        Button {
                            onSizeChange(size)
                        } label: {
                            if size == module.size {
                                Label(size.displayName, systemImage: "checkmark")
                            } else {
                                Text(size.displayName)
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    onHide()
                } label: {
                    Label("Remove Module", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.primary.opacity(0.9))
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                )
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
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModuleID = nil
        return true
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
    @EnvironmentObject var userService: UserService
    let module: DashboardModule
    var isEditing: Bool = false
    var headerAccessory: AnyView? = nil
    
    var body: some View {
        DashboardModuleCardChrome(
            module: module,
            isEditing: isEditing,
            headerAccessory: headerAccessory
        ) {
            if !hasHealthAccess && module.type.requiresHealthAccess {
                DashboardHealthAccessPlaceholder(module: module)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(DashboardModuleVisualSpec(module.size).contentPadding)
            } else {
                DashboardModuleContent(module: module)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(DashboardModuleVisualSpec(module.size).contentPadding)
            }
        }
    }

    private var hasHealthAccess: Bool {
        (userService.currentUser?.allowHealthAccess ?? false) || (userService.currentUser?.isDemo ?? false)
    }
}

struct DashboardModuleCardChrome<Content: View>: View {
    let module: DashboardModule
    let isEditing: Bool
    let headerAccessory: AnyView?
    let content: Content

    init(
        module: DashboardModule,
        isEditing: Bool,
        headerAccessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.module = module
        self.isEditing = isEditing
        self.headerAccessory = headerAccessory
        self.content = content()
    }

    var body: some View {
        let spec = DashboardModuleVisualSpec(module.size)

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    Color(.secondarySystemBackground)
                        .opacity(isEditing ? 0.34 : 0.16)
                )

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: module.type.iconName)
                        .foregroundColor(.secondary)
                        .font(.body)

                    Text(module.type.displayName)
                        .font(spec.headerFont)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let headerAccessory {
                        headerAccessory
                    }
                }
                .padding(spec.headerPadding)

                Divider()

                content
                    .allowsHitTesting(!isEditing)
            }
            .glassEffect(in: .rect(cornerRadius: 12.0))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isEditing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.02))
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.25)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
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

struct DashboardHealthAccessPlaceholder: View {
    let module: DashboardModule

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: module.type.iconName)
                .font(.title3.weight(.semibold))
                .foregroundColor(.secondary)

            Text("Connect Apple Health")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Text("\(module.type.displayName) will appear here once Health access is enabled.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            FitSightModuleView()
        case .nutrition:
            NutritionModuleView(module: module)
        case .sessionVolume:
            SessionVolumeModuleView(module: module)
        }
    }
}

struct FitSightModuleView: View {
    var body: some View {
        NavigationLink(destination: TrueSightView().appBackground()) {
            MetricCard(
                value: "View"
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
                    value: smallCardValue,
                    pageNav: true
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

    private var refreshID: String {
        "\(userService.currentUser?.id.uuidString ?? "none")-\(healthKitDailyStore.refreshToken)"
    }
    
    var body: some View {
        MetricCard(
            value: currentWeight.map { String(format: "%.1f", $0) } ?? "N/A"
        )
        .task(id: refreshID) {
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

    private var refreshID: String {
        "\(userService.currentUser?.id.uuidString ?? "none")-\(healthKitDailyStore.refreshToken)"
    }
    
    var body: some View {
        if module.size == .medium || module.size == .large {
            NavigationLink(destination: HealthHistoryChartView().appBackground()) {
                StepBarGraph(
                    height: module.size == .large ? 132 : 82,
                    barColor: .blue
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        } else {
            NavigationLink(destination: HealthHistoryChartView().appBackground()) {
                MetricCard(
                    value: String(weeklyStepsTotal.rounded())
                )
            }
            .task(id: refreshID) {
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

    private var refreshID: String {
        "\(userService.currentUser?.id.uuidString ?? "none")-\(healthKitDailyStore.refreshToken)"
    }
    
    var body: some View {
        Group {
            if let sleepHours {
                MetricCard(
                    value: String(format: "%.1f", sleepHours) + " hrs",
                    alignment: .center
                )
            } else {
                MetricCard(
                    value: "N/A",
                    alignment: .center
                )
            }
        }
        .task(id: refreshID) {
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

    private var refreshID: String {
        "\(userService.currentUser?.id.uuidString ?? "none")-\(healthKitDailyStore.refreshToken)"
    }
    
    var body: some View {
        Group {
            if let ars = ringStatus {
                MetricActivityRingCard(
                    activityRings: ars,
                    alignment: .center
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                MetricCard(
                    value: "Loading...",
                    alignment: .center
                )
            }
        }
        .task(id: refreshID) {
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
                value: timerService.timer != nil ? timerService.formatted : "--:--",
                pageNav: true
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
                value: String(workoutCount),
                pageNav: true
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
