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
    
    var body: some View {
        List {
            ForEach(splitDayService.routines,  id: \.id) { routine in
                NavigationLink {
                    SingleDayView(routine: routine)
                } label: {
                    SingleDayLabelView(routine: routine)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteRoutine(routine)
                    } label: {
                        let isArchive = splitDayService.willArchiveOnDelete(routine)
                        Label(isArchive ? "Archive" : "Delete", systemImage: isArchive ? "archivebox" : "trash")
                    }
                }
            }
            .onDelete(perform: splitDayService.removeSplitDay)
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
        guard let index = splitDayService.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        splitDayService.removeSplitDay(offsets: IndexSet(integer: index))
    }

}
