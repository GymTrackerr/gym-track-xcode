import SwiftUI
import WidgetKit

struct CreateLogWidgetEntry: TimelineEntry {
    let date: Date
}

struct CreateLogWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CreateLogWidgetEntry {
        CreateLogWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CreateLogWidgetEntry) -> Void) {
        completion(CreateLogWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreateLogWidgetEntry>) -> Void) {
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21_600)
        completion(Timeline(entries: [CreateLogWidgetEntry(date: now)], policy: .after(nextRefresh)))
    }
}

struct CreateLogWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "gymtracker://nutrition/log"))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.green, .blue)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Create")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text("Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Nutrition / Session")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }

    private var mediumLayout: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Create Log")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text("Choose what to add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)

            Link(destination: URL(string: "gymtracker://nutrition/log")!) {
                actionTile(
                    title: "Nutrition",
                    subtitle: "Food or quick add",
                    systemImage: "fork.knife",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "gymtracker://sessions/log")!) {
                actionTile(
                    title: "Session",
                    subtitle: "Workout log",
                    systemImage: "figure.strengthtraining.traditional",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private func actionTile(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct CreateLogWidget: Widget {
    let kind = "CreateLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CreateLogWidgetProvider()) { _ in
            CreateLogWidgetEntryView()
        }
        .supportedFamilies([.systemSmall, .systemMedium])
        .configurationDisplayName("Create Log")
        .description("Opens nutrition or session logging.")
    }
}

#Preview(as: .systemSmall) {
    CreateLogWidget()
} timeline: {
    CreateLogWidgetEntry(date: Date())
}
