//
//  SingleExerciseView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import Charts
import WebKit

struct SingleExerciseView: View {
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil
    
    var body: some View {
        VStack {
            if (exercise.isUserCreated) {
                VStack(alignment: .leading) {
                    if (orderInSplit != nil) {
                        Text("Order in Split: \(orderInSplit ?? 0)")
                    }
                    Text("Exercise: \(exercise.name)")
                    Text("Alises: \(exercise.aliases?.joined(separator: ", ") ?? "")")
                    Text("Muscle Groups: \(exercise.primary_muscles?.joined(separator: ", ") ?? "")")
                    Text("Date: \(exercise.timestamp.formatted(date: .numeric, time: .omitted))")
                    Text("Exercise Type: \(exercise.exerciseType.name)")
                }
                .padding()
                Spacer()
            } else {
                ExerciseDetailView(exercise: exercise)
            }
        }
        .navigationTitle(exercise.name)
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @EnvironmentObject var exerciseService: ExerciseService

    @State private var showHowToPerform = true
    @State private var showMistakes = false
    @State private var selectedTab = "Max Weight"
    
    // Example progress data
    struct ProgressPoint: Identifiable {
        let id = UUID()
        let month: String
        let value: Double
    }
    
    let progressData = [
        ProgressPoint(month: "Jun", value: 50),
        ProgressPoint(month: "Jul", value: 90),
        ProgressPoint(month: "Aug", value: 110)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                if let gifURL = exerciseService.gifURL(for: exercise) {
                    CachedMediaView(url: gifURL)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
                
                DisclosureGroup(isExpanded: $showHowToPerform) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let instructions = exercise.instructions {
                            ForEach(Array(instructions.enumerated()), id: \.offset) { i, step in
                                Text("\(i + 1). \(step)")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("How to Perform")
                        .font(.headline)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your Progress")
                        .font(.headline)
                    
                    HStack {
                        ForEach(["Max Weight", "Total Volume", "Reps"], id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab)
                                    .font(.subheadline)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(selectedTab == tab
                                                ? Color.green.opacity(0.2)
                                                : Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(selectedTab == tab ? .green : .primary)
                            }
                        }
                    }
                    
                    Chart(progressData) { point in
                        LineMark(
                            x: .value("Month", point.month),
                            y: .value("Value", point.value)
                        )
                        .symbol(.circle)
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 160)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Button {
                    print("Log exercise pressed")
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Log this Exercise")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                Button {
                    print("add to Split pressed")
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Split")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.85, green: 0.1, blue: 0.1),//.red,
                    Color.clear//gray.opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 400)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        )
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SingleExerciseLabelView: View {
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil

    var body : some View {
        VStack (alignment: .leading, spacing: 4) {
            ZStack {
                if (exercise.isUserCreated) {
                    VStack(alignment: .leading) {
                        Text(exercise.name)
                        HStack {
                            if (orderInSplit != nil) {
                                Text("Order \((orderInSplit ?? 0)+1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            Text(exercise.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    DetailedExerciseLabelView(exercise: exercise, orderInSplit: orderInSplit)
                }
            }
        }


        .padding(8)
//        .background/*(*/Color.gray.opacity(0.1))
        .cornerRadius(12)
//        .padding(.vertical, 4)
//        .padding(.horizontal, 8)
    }
}

struct DetailedExerciseLabelView: View {
    @EnvironmentObject var exerciseService: ExerciseService
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil
    
    var body: some View {
        HStack {
//                            Text(apiExercise.images.first ?? "")
            if let thumbnailURL = exerciseService.thumbnailURL(for: exercise) {
                CachedMediaView(url: thumbnailURL)
//                    .resizable()
                    .scaledToFill()
                    .frame(width: 45, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .clipped()
                    .padding(.trailing, 8) // Add space between the image and text


            }
             

            VStack {
                HStack {
                    Text(exercise.name)
                    Spacer()
                }
                if let orderInSplit = orderInSplit {
                    HStack {
                        Text("Order \((orderInSplit)+1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

struct GIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
