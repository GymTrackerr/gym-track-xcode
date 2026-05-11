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
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Log")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 8) {
                smallActionButton(
                    title: "Nutrition",
                    systemImage: "fork.knife",
                    tint: .green,
                    destination: "gymtracker://nutrition/log"
                )

                smallActionButton(
                    title: "Session",
                    systemImage: "figure.strengthtraining.traditional",
                    tint: .blue,
                    destination: "gymtracker://sessions/log"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(13)
        .widgetURL(URL(string: "gymtracker://home"))
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            Link(destination: URL(string: "gymtracker://nutrition/log")!) {
                actionRow(
                    title: "Nutrition",
                    subtitle: "Food, meal, or quick add",
                    systemImage: "fork.knife",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "gymtracker://sessions/log")!) {
                actionRow(
                    title: "Session",
                    subtitle: "Workout log",
                    systemImage: "figure.strengthtraining.traditional",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .widgetURL(URL(string: "gymtracker://home"))
    }

    private func actionRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(tint)
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func smallActionButton(title: String, systemImage: String, tint: Color, destination: String) -> some View {
        Link(destination: URL(string: destination)!) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                HStack(spacing: 3) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
