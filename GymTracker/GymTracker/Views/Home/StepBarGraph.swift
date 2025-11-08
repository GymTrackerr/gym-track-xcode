//
//  StepBarGraph.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-08.
//

import SwiftUI
import Charts

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(String(value))
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
        )
        .padding()
    }
}


struct StepBarGraph: View {
    @EnvironmentObject var hkManager: HealthKitManager
    
    struct DayStep: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var data: [DayStep] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: Date())!
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let value = hkManager.weeklySteps.indices.contains(offset) ? hkManager.weeklySteps[offset] : 0
            return DayStep(date: date, value: value)
        }
    }

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Steps", item.value)
            )
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortDay(from: date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let steps = value.as(Double.self) {
                        if steps == 0 {
                            Text("0")
                        } else if steps >= 1000 {
                            Text("\(Int(steps / 1000))k")
                        } else {
                            Text("\(Int(steps))")
                        }
                    }
                }
            }
        }
        .frame(height: 140)
    }

    private func shortDay(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f.string(from: date)
    }
}
