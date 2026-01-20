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
//                .background(
//                    RoundedRectangle(cornerRadius: 16)
//                        .fill(Color(.systemBackground))
//                        .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
//                )
                .glassEffect(in: .rect(cornerRadius: 16.0))

//                .padding()
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
//                    .background(.ultraThinMaterial)
//                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                    .shadow(radius: 6, y: 3)

                    .glassEffect(in: .rect(cornerRadius: 16.0))

//                    .background(
//                        RoundedRectangle(cornerRadius: 16)
//                            .fill(Color(.systemBackground))
//                            .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
//                    )
//                    .padding(.horizontal)
                    
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
                    SessionSelectSplit()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("e.g., Feeling strong today, focus on form.", text: $sessionService.create_notes)
                        
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
                            )
                            .padding()
                    }

                    Button {
                        openedSession = sessionService.addSession()
                    } label: {
                        Text("Start Session")
                            .font(.headline)
                    }
                    
                    .buttonStyle(.plain)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                    Spacer()
                }
                .padding()
                .navigationTitle("New Session")
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


struct SessionSelectSplit2 : View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: SplitDayService
    @Bindable var session: Session

    var body: some View {
        VStack {
            ForEach(splitDayService.splitDays, id: \.id) { splitDay in
                Button {
                    print("updated splitday of session")

                    if (session.splitDay == splitDay) {
                        session.splitDay = nil
                    } else {
                            session.splitDay = splitDay
                    }
                } label: {
                    HStack {
                        Text(splitDay.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
//                        if let currentSession = session {
//                            Image(systemName: currentSession.splitDay == splitDay
//                                  ? "checkmark.circle.fill"
//                                  : "circle")
//                            .font(.title3)
//                            .foregroundStyle(currentSession.splitDay == splitDay ? .green : .gray.opacity(0.4))
//                        } else {
                            Image(systemName: sessionService.selected_splitDay == splitDay
                                  ? "checkmark.circle.fill"
                                  : "circle")
                            .font(.title3)
                            .foregroundStyle(sessionService.selected_splitDay == splitDay ? .green : .gray.opacity(0.4))
//                        }
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
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            
        }
    }
}

struct SessionSelectSplit : View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: SplitDayService
//    @State var session: Session? = nil
//    @State var changingCurrent: Bool = false
//    @State var session: Session?
//    @Binding
    var body: some View {
        VStack {
            ForEach(splitDayService.splitDays, id: \.id) { splitDay in
                Button {
                    if (sessionService.selected_splitDay == splitDay) {
                        sessionService.selected_splitDay = nil
                    } else {
                        sessionService.selected_splitDay = splitDay
                    }
                } label: {
                    HStack {
                        Text(splitDay.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()

                        Image(systemName: sessionService.selected_splitDay == splitDay
                              ? "checkmark.circle.fill"
                              : "circle")
                        .font(.title3)
                        .foregroundStyle(sessionService.selected_splitDay == splitDay ? .green : .gray.opacity(0.4))
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
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            
        }
    }
}

