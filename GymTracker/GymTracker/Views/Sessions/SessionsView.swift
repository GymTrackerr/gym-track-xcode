//
//  SplitDaysView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

// TODO: completion of sessions - similar to completion of sessionexercises

struct SessionsView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: SplitDayService
    @Binding var openedSession: Session?
    
    var body: some View {
        List {
            HStack {
                Button {
                    sessionService.creating_session = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Session")
                    }
                }
            }
            
            if !sessionService.sessions.isEmpty {
                Section {
                    HStack {
                        Text("Previous Sessions")
                    }
                    ForEach(sessionService.sessions.reversed(), id: \.self) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                        } label: {
                            SingleSessionLabelView(session: session)
                        }
                    }
                    .onDelete(perform: sessionService.removeSession)
                }
            }
        }
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
        }
        .sheet(isPresented: $sessionService.creating_session) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Create Your New Session")
                        .font(.headline)
                    
                    TextField("Notes", text: $sessionService.create_notes)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    /* select day*/
                    if let splitDay = sessionService.selected_splitDay {
                        Text("Selected Split Day: \(splitDay.name)")
                        Button {
                            sessionService.selected_splitDay = nil
                        } label: {
                            Text("Unselect Split")
                        }
                    } else {
                        List {
                            ForEach(splitDayService.splitDays, id: \.id) { splitDay in
                                Button(action: {
                                    sessionService.selected_splitDay = splitDay
                                }) {
                                    HStack {
                                        Image(systemName: "scope")
                                        Text(splitDay.name)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                    Spacer()
                    Button {
                        openedSession = sessionService.addSession()
                    } label: {
                        Label("Save", systemImage: "plus.circle")
                            .font(.title2)
                            .padding()
                    }
                    Spacer()
                }
                .padding()
                .navigationTitle("Create New Session")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            sessionService.creating_session = false
                            sessionService.create_notes = ""
                            sessionService.selected_splitDay = nil
                        }
                    }
                }
            }
        }
    }
}

