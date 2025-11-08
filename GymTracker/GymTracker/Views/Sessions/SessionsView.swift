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
//    @State private var isEditing = false

    var body: some View {
        VStack {
            HStack {
                Button {
                    sessionService.creating_session = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Session")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                    }
                }
                .buttonStyle(.plain)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
                )
                .padding()
            }

            
            if !sessionService.sessions.isEmpty {
                HStack {
                    Text("Previous Sessions")
                        .font(.headline)
                        .padding(.horizontal)
                        .underline()
                        .padding(.top, 8)
                }
                
                ForEach(sessionService.sessions.reversed(), id: \.self) { session in
                    NavigationLink {
                        SingleSessionView(session: session)
                    } label: {
                        SingleSessionLabelView(session: session)
                            .foregroundColor(.primary)
                    }
                    .contextMenu {
                        Button {
                            openedSession = session
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            sessionService.removeSession(session: session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    // TODO: Figure out solution for scrollview
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                           Button(role: .destructive) {
                               sessionService.removeSession(session: session)
                           } label: {
                               Label("Delete", systemImage: "trash")
                           }
                       }
                    .buttonStyle(.plain)
                    
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
                    )
                    .padding()
                    
                }
            }
        }
//        .toolbar {
//#if os(iOS)
//            ToolbarItem(placement: .navigationBarTrailing) {
//                EditButton()
//            }
//#endif
//        }
        .sheet(isPresented: $sessionService.creating_session) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Create Your New Session")
                        .font(.headline)
                    
                    TextField("Notes", text: $sessionService.create_notes)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    /* select day*/
                    /*
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
                     */
                    SessionSelectSplit()
                    
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

struct SessionSelectSplit : View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: SplitDayService
    
//    @Binding
    var body: some View {
        VStack {
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
        }
    }
}
