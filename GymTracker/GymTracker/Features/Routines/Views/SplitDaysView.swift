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
                        .cardListRowContentPadding()
                }
                .cardListRowStyle()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteRoutine(routine)
                    } label: {
                        let isArchive = splitDayService.willArchiveOnDelete(routine)
                        Label(isArchive ? "Archive" : "Delete", systemImage: isArchive ? "archivebox" : "trash")
                    }
                }
            }
            .onDelete(perform: deleteRoutinesFromOffsets)
            .onMove(perform: splitDayService.moveSplitDay)

            if splitDayService.routines.isEmpty {
                EmptyStateView(
                    title: "No routines yet",
                    systemImage: "figure.walk.motion",
                    message: "Create a routine to see it here."
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .cardListScreen()
        .appBackground()
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "Routine")

                        ConnectedCardSection {
                            ConnectedCardRow {
                                LabeledContent("Name") {
                                    TextField("Required", text: $splitDayService.editingContent)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }

                        Button {
                            _ = splitDayService.addSplitDay()
                        } label: {
                            Label("Save", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .screenContentPadding()
                }
                .navigationTitle("Create New Routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            splitDayService.editingSplit = false
                            splitDayService.editingContent = ""
                        }
                    }
                }
            }
            .appBackground()
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
        }
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
