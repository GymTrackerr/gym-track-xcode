import SwiftUI
import WidgetKit

struct NutritionLogWidgetEntry: TimelineEntry {
    let date: Date
}

struct NutritionLogWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionLogWidgetEntry {
        NutritionLogWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionLogWidgetEntry) -> Void) {
        completion(NutritionLogWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionLogWidgetEntry>) -> Void) {
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21_600)
        completion(Timeline(entries: [NutritionLogWidgetEntry(date: now)], policy: .after(nextRefresh)))
    }
}

struct NutritionLogWidgetEntryView: View {
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
                .foregroundStyle(.green)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Log")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text("Nutrition")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.16))
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("Log Nutrition")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text("Food, meal, or quick add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}

struct NutritionLogWidget: Widget {
    let kind = "NutritionLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionLogWidgetProvider()) { entry in
            NutritionLogWidgetEntryView()
        }
        .supportedFamilies([.systemSmall, .systemMedium])
        .configurationDisplayName("Log Nutrition")
        .description("Opens nutrition logging.")
    }
}

#Preview(as: .systemSmall) {
    NutritionLogWidget()
} timeline: {
    NutritionLogWidgetEntry(date: Date())
}
