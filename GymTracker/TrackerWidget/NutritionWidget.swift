import SwiftUI
import WidgetKit

struct NutritionWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: NutritionWidgetSnapshot
}

struct NutritionWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionWidgetEntry {
        NutritionWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionWidgetEntry) -> Void) {
        completion(NutritionWidgetEntry(date: Date(), snapshot: NutritionWidgetSnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = NutritionWidgetSnapshotStore.load() ?? .empty
        let entry = NutritionWidgetEntry(date: now, snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct NutritionWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: NutritionWidgetEntry

    private var snapshot: NutritionWidgetSnapshot {
        entry.snapshot
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "gymtracker://nutrition"))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader

            VStack(alignment: .leading, spacing: 4) {
                Text(formatWhole(snapshot.eatenCalories))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(calorieTargetText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            NutritionWidgetProgressBar(progress: snapshot.calorieProgress, tint: .green)

            Spacer(minLength: 0)

            if let burned = snapshot.totalBurnedCalories {
                HStack {
                    stat("Burned", value: formatWhole(burned))
                    Spacer(minLength: 8)
                    stat("Balance", value: balanceText)
                }
            } else {
                Text(snapshot.hasNutritionData ? "Burn unavailable" : "No logs today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                widgetHeader
                Spacer()
                Text("Updated \(snapshot.updatedAt, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calories")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatWhole(snapshot.eatenCalories))
                            .font(.title2.bold())
                        Text("kcal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(calorieTargetText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    NutritionWidgetProgressBar(progress: snapshot.calorieProgress, tint: .green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    burnBalanceRow
                    macroRows
                }
            }
        }
        .padding(14)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                widgetHeader
                Spacer()
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                NutritionWidgetMetricBlock(
                    title: "Eaten",
                    value: formatWhole(snapshot.eatenCalories),
                    unit: "kcal",
                    tint: .green
                )
                NutritionWidgetMetricBlock(
                    title: "Burned",
                    value: snapshot.totalBurnedCalories.map(formatWhole) ?? "--",
                    unit: "kcal",
                    tint: .orange
                )
                NutritionWidgetMetricBlock(
                    title: "Balance",
                    value: balanceText,
                    unit: "kcal",
                    tint: balanceTint
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(calorieTargetText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                NutritionWidgetProgressBar(progress: snapshot.calorieProgress, tint: .green)
            }

            macroRows

            if !snapshot.goalSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Goals")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(snapshot.goalSnapshots) { goal in
                        NutritionWidgetGoalRow(goal: goal)
                    }
                }
            } else {
                Text(snapshot.hasNutritionData ? "No nutrient goals set" : "No nutrition logged today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
            Text("Nutrition")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var burnBalanceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                stat("Burned", value: snapshot.totalBurnedCalories.map(formatWhole) ?? "--")
                Spacer()
                stat("Balance", value: balanceText)
            }
        }
    }

    private var macroRows: some View {
        VStack(spacing: 6) {
            NutritionWidgetMacroRow(name: "Protein", value: snapshot.protein, target: snapshot.proteinTarget, tint: .blue)
            NutritionWidgetMacroRow(name: "Carbs", value: snapshot.carbs, target: snapshot.carbsTarget, tint: .purple)
            NutritionWidgetMacroRow(name: "Fat", value: snapshot.fat, target: snapshot.fatTarget, tint: .pink)
        }
    }

    private var calorieTargetText: String {
        guard let target = snapshot.calorieTarget else {
            return "\(formatWhole(snapshot.eatenCalories)) kcal eaten"
        }
        let remaining = max(target - snapshot.eatenCalories, 0)
        return "\(formatWhole(remaining)) left of \(formatWhole(target))"
    }

    private var balanceText: String {
        guard let balance = snapshot.energyBalance else { return "--" }
        let rounded = Int(balance.rounded())
        if rounded > 0 { return "+\(rounded)" }
        return "\(rounded)"
    }

    private var balanceTint: Color {
        guard let balance = snapshot.energyBalance else { return .secondary }
        return balance <= 0 ? .blue : .orange
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func formatWhole(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0)))
    }
}

private struct NutritionWidgetMetricBlock: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NutritionWidgetMacroRow: View {
    let name: String
    let value: Double
    let target: Double?
    let tint: Color

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(name)
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            NutritionWidgetProgressBar(progress: progress, tint: tint)
        }
    }

    private var summary: String {
        let valueText = "\(Int(value.rounded()))g"
        guard let target, target > 0 else { return valueText }
        return "\(valueText) / \(Int(target.rounded()))g"
    }
}

private struct NutritionWidgetGoalRow: View {
    let goal: NutritionWidgetGoalSnapshot

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(goal.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(formatted(goal.value)) / \(formatted(goal.target))\(goal.unit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            NutritionWidgetProgressBar(progress: goal.progress, tint: .teal)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0)))
    }
}

private struct NutritionWidgetProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * min(max(progress, 0), 1), 3)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: width)
            }
        }
        .frame(height: 6)
    }
}

struct NutritionWidget: Widget {
    let kind = NutritionWidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionWidgetProvider()) { entry in
            NutritionWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .configurationDisplayName("Nutrition")
        .description("Shows today's eaten calories, burned energy, balance, macros, and goals.")
    }
}

#Preview(as: .systemMedium) {
    NutritionWidget()
} timeline: {
    NutritionWidgetEntry(date: Date(), snapshot: .placeholder)
}
