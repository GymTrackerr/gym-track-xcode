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
                .contextMenu {
                    Button(role: .destructive) {
                        deleteRoutine(routine)
                    } label: {
                        let isArchive = splitDayService.willArchiveOnDelete(routine)
                        Label {
                            Text(isArchive
                                 ? LocalizedStringResource("routines.action.archive", defaultValue: "Archive", table: "Routines")
                                 : LocalizedStringResource("routines.action.delete", defaultValue: "Delete", table: "Routines"))
                        } icon: {
                            Image(systemName: isArchive ? "archivebox" : "trash")
                        }
                    }
                }
                .cardListRowStyle()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteRoutine(routine)
                    } label: {
                        let isArchive = splitDayService.willArchiveOnDelete(routine)
                        Label {
                            Text(isArchive
                                 ? LocalizedStringResource("routines.action.archive", defaultValue: "Archive", table: "Routines")
                                 : LocalizedStringResource("routines.action.delete", defaultValue: "Delete", table: "Routines"))
                        } icon: {
                            Image(systemName: isArchive ? "archivebox" : "trash")
                        }
                    }
                }
            }
            .onDelete(perform: deleteRoutinesFromOffsets)
            .onMove(perform: splitDayService.moveSplitDay)

            if splitDayService.routines.isEmpty {
                EmptyStateView(
                    resourceTitle: LocalizedStringResource("routines.empty.title", defaultValue: "No routines yet", table: "Routines"),
                    systemImage: "figure.walk.motion",
                    resourceMessage: LocalizedStringResource("routines.empty.message", defaultValue: "Create a routine to see it here.", table: "Routines")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .cardListScreen()
        .appBackground()
        .navigationTitle(String(localized: LocalizedStringResource("routines.title", defaultValue: "Routines", table: "Routines")))
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
                    Label {
                        Text(LocalizedStringResource("routines.action.addRoutine", defaultValue: "Add Routine", table: "Routines"))
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $splitDayService.editingSplit) {
            NavigationView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(resourceTitle: LocalizedStringResource("routines.section.routine", defaultValue: "Routine", table: "Routines"))

                        ConnectedCardSection {
                            ConnectedCardRow {
                                LabeledContent {
                                    TextField(
                                        text: $splitDayService.editingContent,
                                        prompt: Text(LocalizedStringResource("routines.placeholder.required", defaultValue: "Required", table: "Routines"))
                                    ) {
                                        Text(LocalizedStringResource("routines.field.name", defaultValue: "Name", table: "Routines"))
                                    }
                                        .multilineTextAlignment(.trailing)
                                } label: {
                                    Text(LocalizedStringResource("routines.field.name", defaultValue: "Name", table: "Routines"))
                                }
                            }
                        }

                        Button {
                            _ = splitDayService.addSplitDay()
                        } label: {
                            Label {
                                Text(LocalizedStringResource("routines.action.save", defaultValue: "Save", table: "Routines"))
                            } icon: {
                                Image(systemName: "plus.circle")
                            }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .screenContentPadding()
                }
                .navigationTitle(String(localized: LocalizedStringResource("routines.editor.createNewRoutine", defaultValue: "Create New Routine", table: "Routines")))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            splitDayService.editingSplit = false
                            splitDayService.editingContent = ""
                        } label: {
                            Text(LocalizedStringResource("routines.action.cancel", defaultValue: "Cancel", table: "Routines"))
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

        let message: String
        if archiveCount == toDelete.count {
            message = String(localized: LocalizedStringResource(
                "routines.toast.archiveWithHistory",
                defaultValue: "\(toDelete.count) routines have history and will be archived.",
                table: "Routines"
            ))
        } else if archiveCount == 0 {
            message = String(localized: LocalizedStringResource(
                "routines.toast.deleteRoutines",
                defaultValue: "Delete \(toDelete.count) routines?",
                table: "Routines"
            ))
        } else {
            let deleteCount = toDelete.count - archiveCount
            message = String(localized: LocalizedStringResource(
                "routines.toast.archiveAndDelete",
                defaultValue: "Will archive \(archiveCount), delete \(deleteCount).",
                table: "Routines"
            ))
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
