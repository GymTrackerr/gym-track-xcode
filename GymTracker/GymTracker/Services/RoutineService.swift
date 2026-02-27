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
    
    override func loadFeature() {
        self.loadSplitDays()
    }
    
    func loadSplitDays() {
        loadActiveRoutines()
        loadArchivedRoutines()
    }

    func loadArchivedRoutines() {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.isArchived == true
            },
            sortBy: [SortDescriptor(\.order)]
        )

        do {
            archivedRoutines = try modelContext.fetch(descriptor)
        } catch {
            archivedRoutines = []
        }
    }

    private func loadActiveRoutines() {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.isArchived == false
            },
            sortBy: [SortDescriptor(\.order)]
        )

        do {
            routines = try modelContext.fetch(descriptor)
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
        routine.aliases = Array(Set(aliases)).sorted()
        do {
            try modelContext.save()
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
        let newItem = Routine(order: nextOrder, name: trimmedName, user_id: userId)
        var failedAdd = false
        withAnimation {
//            let newItem = Routine(order: routines.count, name: trimmedName)
            modelContext.insert(newItem)
            do {
                try modelContext.save()
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
        // For archived items, just unarchive
        if routine.isArchived {
            routine.isArchived = false
        } else {
            // For non-archived items that were deleted, re-insert
            modelContext.insert(routine)
        }
        do {
            try modelContext.save()
            loadSplitDays()
            renumberSplitDays()
        } catch {
            print("Failed to restore routine: \(error)")
        }
    }
    
    func clearSplitDays() {
        let descriptor = FetchDescriptor<Routine>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items {
                try? delete(item)
            }
        }
        loadSplitDays()
    }

    func printSplitDays() {
        let descriptor = FetchDescriptor<Routine>()
        do {
            let items = try modelContext.fetch(descriptor)
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
        for (i, day) in routines.enumerated() {
            day.order = i
        }
        try? modelContext.save()
    }

    func delete(_ routine: Routine) throws {
        // If routine has session history → archive
        if !routine.sessions.isEmpty {
            routine.isArchived = true
            try modelContext.save()
            return
        }

        // No history → mark as archived (soft delete) for undo support
        routine.isArchived = true
        try modelContext.save()
    }

    func willArchiveOnDelete(_ routine: Routine) -> Bool {
        !routine.sessions.isEmpty
    }

    func restore(_ routine: Routine) throws {
        routine.isArchived = false
        try modelContext.save()
        loadSplitDays()
    }
}
