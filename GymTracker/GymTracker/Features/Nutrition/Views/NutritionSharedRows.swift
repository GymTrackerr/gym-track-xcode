import SwiftUI

struct MealRowView: View {
    let meal: MealRecipe

    var body: some View {
        HStack {
            Text(meal.name)
            Spacer()
            Text("\(meal.items.count) items")
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
                    Text(food.name)
                    if food.isArchived {
                        Text("Archived")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .controlCapsuleSurface()
                    }
                }
                if let brand = food.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            trailing
        }
    }
}
