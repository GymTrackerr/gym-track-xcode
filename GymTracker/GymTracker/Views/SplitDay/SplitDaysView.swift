//
//  SplitDaysView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

struct SplitDaysView: View {
    @EnvironmentObject var splitDayService: SplitDayService
    @State private var isAdding: Bool = false
    @State private var selectedSplitDay: SplitDay? = nil
    @State private var newSplitName: String = ""
    
    var body: some View {
        List {
            ForEach(splitDayService.splitDays) { splitDay in
                NavigationLink {
                    SingleDayView(splitDay: splitDay)
                } label: {
                    SingleDayLabelView(splitDay: splitDay)
                }
            }
            .onDelete(perform: splitDayService.removeSplitDay)
            .onMove(perform: splitDayService.moveSplitDay)

        }
        .navigationTitle("Split Days")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Split Day", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Name your new split day")
                        .font(.headline)
                    
                    TextField("Name", text: $splitDayService.editingContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Button {
                        splitDayService.addSplitDay(name: newSplitName)
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    .disabled(splitDayService.editingContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Split Day")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isAdding = false
                            splitDayService.editingContent = ""
                        }
                    }
                }
            }
        }
    }
}

