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
        .widgetURL(URL(string: "gymtracker://programme"))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            smallHeader

            VStack(alignment: .leading, spacing: 4) {
                Text(smallPrimaryText)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)

                Text(smallSecondaryText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ProgrammeWidgetStatusBar(isActive: snapshot.hasProgramme, tint: .green)

            Spacer(minLength: 0)

            if snapshot.hasActiveSession {
                HStack {
                    smallStat("Session", value: "Active")
                    Spacer(minLength: 8)
                    smallStat("Now", value: snapshot.activeSessionName ?? "Open")
                }
            } else if let status = smallFooterText {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                Text(snapshot.hasProgramme ? "Ready" : "No active programme")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 10) {
                widgetPanel(
                    title: "Active Programme",
                    value: snapshot.activeProgrammeName ?? "None active",
                    detail: nextRoutineDetail ?? snapshot.programmeStatus,
                    tint: .green
                )

                activeSessionPanel
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

            activeSessionPanel

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

    private var smallHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk.motion")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Programme")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var smallPrimaryText: String {
        if snapshot.hasProgramme {
            return snapshot.activeProgrammeName ?? "Programme"
        }
        return "No Programme"
    }

    private var smallSecondaryText: String {
        if let nextRoutineDetail, !nextRoutineDetail.isEmpty {
            return nextRoutineDetail
        }
        if let status = snapshot.programmeStatus, !status.isEmpty {
            return status
        }
        return snapshot.hasProgramme ? "Open programme" : "Activate in app"
    }

    private var smallFooterText: String? {
        [snapshot.programmeStatus, snapshot.programmeDetail]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    private var nextRoutineDetail: String? {
        snapshot.nextWorkoutName.map { "Next: \($0)" }
    }

    private var programmeSummary: String {
        [
            snapshot.programmeStatus,
            snapshot.programmeDetail,
            nextRoutineDetail
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    @ViewBuilder
    private var activeSessionPanel: some View {
        if snapshot.hasActiveSession {
            Link(destination: URL(string: "gymtracker://sessions/active")!) {
                widgetPanel(
                    title: "Active Session",
                    value: snapshot.activeSessionName ?? "Open Session",
                    detail: snapshot.activeSessionDetail,
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
        } else {
            widgetPanel(
                title: "Active Session",
                value: "No active session",
                detail: "Open Sessions to start one",
                tint: .blue
            )
        }
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

    private func smallStat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct ProgrammeWidgetStatusBar: View {
    let isActive: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.16))

                Capsule()
                    .fill(isActive ? tint : tint.opacity(0.35))
                    .frame(width: proxy.size.width * (isActive ? 0.78 : 0.24))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
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
        .description("Shows your active programme and next routine.")
    }
}

#Preview(as: .systemMedium) {
    ProgrammeWidget()
} timeline: {
    ProgrammeWidgetEntry(date: Date(), snapshot: .placeholder)
}
