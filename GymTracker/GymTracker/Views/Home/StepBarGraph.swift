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
    @State var alignment: HorizontalAlignment = .leading
    @State var pageNav: Bool = false

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Text(String(value))
                    .font(.title3)
                    .fontWeight(.semibold)
                if (pageNav) {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 16.0))
//        .background(
//            RoundedRectangle(cornerRadius: 16)
//                .fill(Color(.systemBackground))
//                .shadow(color: .gray.opacity(0.2), radius: 4, y: 2)
//        )
        
    }
}

struct MetricActivityRingCard: View {
    let title: String
    let activityRings: ActivityRingStatus
    @State var alignment: HorizontalAlignment = .leading
    
    var body: some View {
        VStack(alignment: alignment, spacing: 12) {
            Label(title, systemImage: "gauge.with.needle")
                .font(.subheadline)
                .foregroundColor(.secondary)

            
            HStack(spacing: 20) {
                if (alignment == .center) {
                    Spacer()
                }
                // Move Ring
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        
                        Circle()
                            .trim(from: 0, to: min(activityRings.moveRingPercentage / 100, 1.0))
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 2) {
                            Text("\(Int(activityRings.moveRingValue))")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 60, height: 60)
                    
                    Text("Move")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if (alignment == .center) {
                    Spacer()
                }
                
                // Exercise Ring
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        
                        Circle()
                            .trim(from: 0, to: min(activityRings.exerciseRingPercentage / 100, 1.0))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 2) {
                            Text("\(Int(activityRings.exerciseRingValue))")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Min")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 60, height: 60)
                    
                    Text("Exercise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if (alignment == .center) {
                    Spacer()
                }
                // Stand Ring
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        
                        Circle()
                            .trim(from: 0, to: min(Double(activityRings.standRingPercentage) / 100, 1.0))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 2) {
                            Text("\(activityRings.standRingValue)")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("hrs")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 60, height: 60)
                    
                    Text("Stand")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16.0))
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
