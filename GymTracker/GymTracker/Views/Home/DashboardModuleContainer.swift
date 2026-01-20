import SwiftUI

struct DashboardModuleContainer<Content: View>: View {
    let module: DashboardModule
    let dashboardService: DashboardService
    let content: () -> Content
    
    @State private var showSizeEditor = false
    @State private var selectedSize: ModuleSize
    @State var needsGlass: Bool = false
    
    init(
        module: DashboardModule,
        dashboardService: DashboardService,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.module = module
        self.dashboardService = dashboardService
        self.content = content
        _selectedSize = State(initialValue: module.size)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onLongPressGesture {
            showSizeEditor = true
        }
        .sheet(isPresented: $showSizeEditor) {
            ModuleEditorView(
                module: module,
                dashboardService: dashboardService,
                isPresented: $showSizeEditor
            )
        }
    }
}

struct ModuleEditorView: View {
    let module: DashboardModule
    let dashboardService: DashboardService
    @Binding var isPresented: Bool
    @State private var selectedSize: ModuleSize
    
    init(
        module: DashboardModule,
        dashboardService: DashboardService,
        isPresented: Binding<Bool>
    ) {
        self.module = module
        self.dashboardService = dashboardService
        self._isPresented = isPresented
        _selectedSize = State(initialValue: module.size)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Module Settings")) {
                    Text(module.type.displayName)
                        .font(.headline)
                    
                    Picker("Size", selection: $selectedSize) {
                        ForEach(module.type.allowedSizes, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Toggle("Visible", isOn: Binding(
                        get: { module.isVisible },
                        set: { _,_ in dashboardService.toggleModuleVisibility(module.id) }
                    ))
                }
            }
            .navigationTitle(module.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dashboardService.updateModuleSize(module.id, newSize: selectedSize)
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
