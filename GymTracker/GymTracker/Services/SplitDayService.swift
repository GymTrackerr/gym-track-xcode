//
//  SplitDayService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//
import SwiftUI
import SwiftData
import Combine
internal import CoreData

class SplitDayService : ServiceBase, ObservableObject {
    @Published var splitDays: [SplitDay] = []

    @Published var editingContent: String = ""
    @Published var editingSplit: Bool = false
    
    override func loadFeature() {
        self.loadSplitDays()
    }
    
    func loadSplitDays() {
        let descriptor = FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.order)])

        do {
            splitDays = try modelContext.fetch(descriptor)
        } catch {
            splitDays = []
        }
    }
    
    func addSplitDay(name: String) {
        print("Adding")
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        withAnimation {
            let newItem = SplitDay(order: splitDays.count, name: trimmedName)
            modelContext.insert(newItem)
            do {
                try modelContext.save()
                // Clear and dismiss sheet after successful save
                editingSplit = false
                editingContent = ""
                loadSplitDays()

            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }
    
    func removeSplitDay(offsets: IndexSet) {
        print("not activating")
        withAnimation {
            for index in offsets {
                modelContext.delete(splitDays[index])
            }
            renumberSplitDays()
            do {
                try modelContext.save()
                loadSplitDays()

            } catch {
                print("Failed to save after deletion: \(error)")
            }
        }
    }
    
    func moveSplitDay(from source: IndexSet, to destination: Int) {
        print("not activating")

        var updated = splitDays
        updated.move(fromOffsets: source, toOffset: destination)
        
        for (i, day) in updated.enumerated() {
            day.order = i
        }
        
        try? modelContext.save()
        loadSplitDays()
    }

    
    func renumberSplitDays() {
        for (i, day) in splitDays.enumerated() {
            day.order = i
        }
        loadSplitDays()
    }
}
