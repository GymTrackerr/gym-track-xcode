//
//  SplitDaysView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

struct SplitDaysView: View {
    @EnvironmentObject var splitDayService: RoutineService
    @Environment(\.editMode) private var editMode
    @State private var isAdding: Bool = false
    @EnvironmentObject var toastManager: ActionToastManager
    
    var body: some View {
        List {
            ForEach(splitDayService.routines,  id: \.id) { routine in
                NavigationLink {
                    SingleDayView(routine: routine)
                } label: {
                    SingleDayLabelView(routine: routine)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !routine.isBuiltIn {
                        Button(role: .destructive) {
                            deleteRoutine(routine)
                        } label: {
                            let isArchive = splitDayService.willArchiveOnDelete(routine)
                            Label(isArchive ? "Archive" : "Delete", systemImage: isArchive ? "archivebox" : "trash")
                        }
                    }
                }
            }
            .onDelete(perform: deleteRoutinesFromOffsets)
            .onMove(perform: splitDayService.moveSplitDay)

            if splitDayService.routines.isEmpty {
                ContentUnavailableView("No routines yet", systemImage: "figure.walk.motion")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Routines")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Button {
                    splitDayService.editingSplit = true
                } label: {
                    Label("Add Routine", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $splitDayService.editingSplit) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Name your new routine")
                        .font(.headline)
                    
                    TextField("Name", text: $splitDayService.editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Button {
                        _ = splitDayService.addSplitDay()
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Routine")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            splitDayService.editingSplit = false
                            splitDayService.editingContent = ""
                        }
                    }
                }
            }
        }
    }

    private func deleteRoutine(_ routine: Routine) {
        deleteRoutinesOptimistic(ids: [routine.id])
    }

    private func deleteRoutinesFromOffsets(offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            splitDayService.routines.indices.contains(index) ? splitDayService.routines[index].id : nil
        }
        deleteRoutinesOptimistic(ids: ids)
    }

    private func deleteRoutinesOptimistic(ids: [UUID]) {
        let toDelete = ids.compactMap { id in
            splitDayService.routines.first(where: { $0.id == id })
        }.filter { !$0.isBuiltIn }
        guard !toDelete.isEmpty else { return }

        let archiveCount = toDelete.reduce(into: 0) { count, routine in
            if splitDayService.willArchiveOnDelete(routine) {
                count += 1
            }
        }

        let offsetsToDelete = toDelete.compactMap { routine in
            splitDayService.routines.firstIndex(where: { $0.id == routine.id })
        }
        if !offsetsToDelete.isEmpty {
            var indexSet = IndexSet()
            for offset in offsetsToDelete {
                indexSet.insert(offset)
            }
            splitDayService.removeSplitDay(offsets: indexSet)
        }

        let isPlural = toDelete.count > 1
        let noun = isPlural ? "routines" : "routine"
        let message: String
        if archiveCount == toDelete.count {
            message = isPlural ? "Routines have history. Will archive \(noun)." : "Routine has history. Will archive \(noun)."
        } else if archiveCount == 0 {
            message = "Delete \(toDelete.count) \(noun)?"
        } else {
            message = "Will archive \(archiveCount), delete \(toDelete.count - archiveCount)."
        }

        let deletedItems = toDelete
        toastManager.add(
            message: message,
            intent: .undo,
            timeout: 4,
            onAction: {
                for routine in deletedItems {
                    splitDayService.addRestoredRoutine(routine)
                }
            }
        )
    }

}
