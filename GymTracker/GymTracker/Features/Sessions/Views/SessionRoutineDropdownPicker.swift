import SwiftUI

struct SessionRoutineDropdownPicker: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var splitDayService: RoutineService

    let initialRoutineId: UUID?

    private var selectedRoutineName: String {
        sessionService.selected_splitDay?.name ?? "No routine"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routine")
                .font(.caption)
                .foregroundColor(.secondary)

            Menu {
                Button {
                    sessionService.selected_splitDay = nil
                } label: {
                    if sessionService.selected_splitDay == nil {
                        Label("No routine", systemImage: "checkmark")
                    } else {
                        Text("No routine")
                    }
                }

                if !splitDayService.routines.isEmpty {
                    Divider()
                }

                ForEach(splitDayService.routines, id: \.id) { routine in
                    Button {
                        sessionService.selected_splitDay = routine
                    } label: {
                        if sessionService.selected_splitDay?.id == routine.id {
                            Label(routine.name, systemImage: "checkmark")
                        } else {
                            Text(routine.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedRoutineName)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemBackground))
                )
            }
        }
        .onAppear {
            if let initialRoutineId,
               let initialRoutine = splitDayService.routines.first(where: { $0.id == initialRoutineId }) {
                sessionService.selected_splitDay = initialRoutine
            } else if initialRoutineId == nil {
                sessionService.selected_splitDay = nil
            }
        }
    }
}
