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
    
    var body: some View {
        HStack {
            Button("Clear Splits") {
                splitDayService.clearSplitDays()
            }
            Button("Print Splits") {
                splitDayService.printSplitDays()
            }
        }

        List {
            ForEach(splitDayService.splitDays,  id: \.id) { splitDay in
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
                    splitDayService.editingSplit = true
                } label: {
                    Label("Add Split Day", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $splitDayService.editingSplit) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Name your new split day")
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
                .navigationTitle("Create New Split Day")
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
}

