import SwiftUI

struct MealRowView: View {
    let meal: MealRecipe

    var body: some View {
        HStack {
            Text(verbatim: meal.name)
            Spacer()
            Text(
                LocalizedStringResource(
                    "nutrition.items.count",
                    defaultValue: "\(meal.items.count) items",
                    table: "Nutrition",
                    comment: "Number of items in a meal"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FoodRowView<Trailing: View>: View {
    let food: FoodItem
    let trailing: Trailing

    init(food: FoodItem, @ViewBuilder trailing: () -> Trailing) {
        self.food = food
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: food.name)
                    if food.isArchived {
                        Text("Archived", tableName: "Nutrition")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .controlCapsuleSurface()
                    }
                }
                if let brand = food.brand {
                    Text(verbatim: brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            trailing
        }
    }
}
