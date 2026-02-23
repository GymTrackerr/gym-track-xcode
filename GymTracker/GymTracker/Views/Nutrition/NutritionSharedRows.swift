import SwiftUI

struct MealRowView: View {
    let meal: Meal

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
    let food: Food
    let trailing: Trailing

    init(food: Food, @ViewBuilder trailing: () -> Trailing) {
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
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
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
