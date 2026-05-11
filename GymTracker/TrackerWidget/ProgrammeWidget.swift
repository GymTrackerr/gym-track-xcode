import SwiftUI
import WidgetKit

struct ProgrammeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ProgrammeWidgetSnapshot
}

struct ProgrammeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgrammeWidgetEntry {
        ProgrammeWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgrammeWidgetEntry) -> Void) {
        completion(ProgrammeWidgetEntry(date: Date(), snapshot: ProgrammeWidgetSnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgrammeWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = ProgrammeWidgetSnapshotStore.load() ?? .empty
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7_200)
        completion(Timeline(entries: [ProgrammeWidgetEntry(date: now, snapshot: snapshot)], policy: .after(nextRefresh)))
    }
}

struct ProgrammeWidgetEntryView: View {
    let entry: ProgrammeWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: ProgrammeWidgetSnapshot {
        entry.snapshot
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            case .systemLarge:
                largeLayout
            default:
                smallLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: snapshot.hasActiveSession ? "gymtracker://sessions" : "gymtracker://programme"))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Spacer(minLength: 0)

            if snapshot.hasActiveSession {
                statusPill("Active Session", tint: .blue)
                titleText(snapshot.activeSessionName ?? "Open Session")
                detailText(snapshot.activeSessionDetail)
            } else if snapshot.hasProgramme {
                statusPill("Active Programme", tint: .green)
                titleText(snapshot.activeProgrammeName ?? "Programme")
                detailText(snapshot.nextWorkoutName.map { "Next: \($0)" })
            } else {
                titleText("No Programme")
                detailText("Activate a programme in the app")
            }
        }
        .padding(16)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 10) {
                widgetPanel(
                    title: "Programme",
                    value: snapshot.activeProgrammeName ?? "None active",
                    detail: snapshot.nextWorkoutName.map { "Next: \($0)" } ?? snapshot.programmeStatus,
                    tint: .green
                )

                widgetPanel(
                    title: "Session",
                    value: snapshot.activeSessionName ?? "No active session",
                    detail: snapshot.activeSessionDetail ?? "Create a log from Sessions",
                    tint: .blue
                )
            }
        }
        .padding(16)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            widgetPanel(
                title: "Active Programme",
                value: snapshot.activeProgrammeName ?? "None active",
                detail: programmeSummary,
                tint: .green
            )

            widgetPanel(
                title: "Active Session",
                value: snapshot.activeSessionName ?? "No active session",
                detail: snapshot.activeSessionDetail ?? "Create a session log when you start training",
                tint: .blue
            )

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk.motion")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Programme")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var programmeSummary: String {
        [
            snapshot.programmeStatus,
            snapshot.programmeDetail,
            snapshot.nextWorkoutName.map { "Next: \($0)" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func widgetPanel(title: String, value: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }

    private func detailText(_ text: String?) -> some View {
        Text(text ?? "")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .opacity(text == nil ? 0 : 1)
    }
}

struct ProgrammeWidget: Widget {
    let kind = ProgrammeWidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgrammeWidgetProvider()) { entry in
            ProgrammeWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .configurationDisplayName("Programme")
        .description("Shows your active programme and active session.")
    }
}

#Preview(as: .systemMedium) {
    ProgrammeWidget()
} timeline: {
    ProgrammeWidgetEntry(date: Date(), snapshot: .placeholder)
}
