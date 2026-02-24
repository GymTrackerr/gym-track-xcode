import SwiftUI

struct SessionsPageView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var exerciseService: ExerciseService
    @EnvironmentObject var userService: UserService

    @State private var openedSession: Session?
    @State private var showingNotesImport = false
    @State private var showingCreateSession = false

    private var sortedSessions: [Session] {
        sessionService.sessions.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        Group {
            if sortedSessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "figure.strengthtraining.traditional")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedSessions, id: \.id) { session in
                        NavigationLink {
                            SingleSessionView(session: session)
                                .appBackground()
                        } label: {
                            SessionsPageRowLabel(session: session)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sessionService.removeSession(session: session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "doc.text") {
                    showingNotesImport = true
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Log", systemImage: "plus") {
                    showingCreateSession = true
                }
            }
        }
        .onAppear {
            sessionService.loadSessions()
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateSessionSheetView(
                openedSession: $openedSession,
                isPresented: $showingCreateSession
            )
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $showingNotesImport) {
            NotesImportView(currentUserId: userService.currentUser?.id) {
                sessionService.loadSessions()
                splitDayService.loadSplitDays()
                exerciseService.loadExercises()
                showingNotesImport = false
            }
        }
        .navigationDestination(item: $openedSession) { session in
            SingleSessionView(session: session)
                .appBackground()
        }
    }
}

private struct SessionsPageRowLabel: View {
    @Bindable var session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.timestamp, format: Date.FormatStyle(date: .long, time: .shortened))

                HStack {
                    Text("\(session.sessionEntries.count) Exercise\(session.sessionEntries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let routine = session.routine {
                        Text("Routine: \(routine.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
            .padding(.trailing, 4)
        }
    }
}
