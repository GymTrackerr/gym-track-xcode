//
//  RoutineService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class RoutineService : ServiceBase, ObservableObject {
    @Published var routines: [Routine] = []
    @Published var archivedRoutines: [Routine] = []

    @Published var editingContent: String = ""
    @Published var editingSplit: Bool = false
    
    @Published var editingNotes: String = ""
    private let repository: RoutineRepositoryProtocol

    init(context: ModelContext, repository: RoutineRepositoryProtocol? = nil) {
        self.repository = repository ?? LocalRoutineRepository(modelContext: context)
        super.init(context: context)
    }
    
    override func loadFeature() {
        self.loadSplitDays()
    }
    
    func loadSplitDays() {
        loadActiveRoutines()
        loadArchivedRoutines()
    }

    func loadArchivedRoutines() {
        guard let userId = currentUser?.id else {
            archivedRoutines = []
            return
        }

        do {
            archivedRoutines = try repository.fetchArchivedRoutines(for: userId)
        } catch {
            archivedRoutines = []
        }
    }

    private func loadActiveRoutines() {
        guard let userId = currentUser?.id else {
            routines = []
            return
        }

        do {
            routines = try repository.fetchActiveRoutines(for: userId)
        } catch {
            routines = []
        }
    }
    
    func search(query: String) -> [Routine] {
        print("searching split days \(query)")

        guard !query.isEmpty else { return routines }
        return routines.filter { routine in
            if routine.name.localizedCaseInsensitiveContains(query) {
                return true
            }
            return routine.aliases.contains { alias in
                alias.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func normalizedAliases(from rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    func setAliases(for routine: Routine, aliases: [String]) -> Bool {
        do {
            try repository.setAliases(aliases, for: routine)
            loadSplitDays()
            return true
        } catch {
            print("Failed to save routine aliases: \(error)")
            return false
        }
    }
    
    func addSplitDay() -> Routine? {
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        guard let userId = currentUser?.id else { return nil }
        
        let nextOrder = (routines.map { $0.order }.max() ?? -1) + 1
        var newItem: Routine?
        var failedAdd = false
        withAnimation {
            do {
                newItem = try repository.createRoutine(name: trimmedName, userId: userId, order: nextOrder)
                editingSplit = false
                editingContent = ""
                loadSplitDays()
            } catch {
                print("Failed to save new split day: \(error)")
                failedAdd = true
            }
        }
        
        if (failedAdd) { return nil }
        return newItem
    }
    
    func removeSplitDay(offsets: IndexSet) {
        withAnimation {
            var failed = false
            for index in offsets {
                do {
                    try delete(routines[index])
                } catch {
                    failed = true
                    print("Failed to save after deletion: \(error)")
                }
            }
            if !failed {
                loadSplitDays()
                renumberSplitDays()
            }
        }
    }
    
    func addRestoredRoutine(_ routine: Routine) {
        do {
            try repository.reinsertOrRestore(routine)
            loadSplitDays()
            renumberSplitDays()
        } catch {
            print("Failed to restore routine: \(error)")
        }
    }
    
    func clearSplitDays() {
        if let items = try? repository.fetchAllRoutines() {
            for item in items {
                try? delete(item)
            }
        }
        loadSplitDays()
    }

    func printSplitDays() {
        do {
            let items = try repository.fetchAllRoutines()
            print("SplitDays count: \(items.count)")
            for item in items {
                print("id: \(item.id), name: \(item.name), order: \(item.order), timestamp: \(item.timestamp)")
            }
        } catch {
            print("Failed to fetch SplitDays: \(error)")
        }
    }

    func moveSplitDay(from source: IndexSet, to destination: Int) {
        withAnimation {
            routines.move(fromOffsets: source, toOffset: destination)
            renumberSplitDays()
        }
    }
    
    func renumberSplitDays() {
        try? repository.renumber(routines)
    }

    func delete(_ routine: Routine) throws {
        try repository.delete(routine)
    }

    func willArchiveOnDelete(_ routine: Routine) -> Bool {
        repository.willArchiveOnDelete(routine)
    }

    func restore(_ routine: Routine) throws {
        try repository.restore(routine)
        loadSplitDays()
    }
}
