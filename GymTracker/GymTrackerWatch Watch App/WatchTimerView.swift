//
//  WatchTimerView.swift
//  GymTrackerWatch Watch App
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI

struct WatchTimerView: View {
    @EnvironmentObject var watchSession: WatchSessionListener
//    @EnvironmentObject var timerService: TimerService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    
                    // Circular Timer
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.25), lineWidth: 18)
                            .padding(10)
                        
                        if watchSession.timer != nil {
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.green, style: .init(lineWidth: 18, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(10)
                                .animation(.linear, value: progress)
                        }
                        
                        Text(timerDisplay)
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }
                    .frame(height: 180)
                    
                    // Top Add When Setting
                    if watchSession.timer == nil {
                        Button(action: { watchSession.addToTimer(seconds: 15) }) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                    }
                    
                    // Bottom Controls
                    HStack(spacing: 14) {
                        
                        if watchSession.timer == nil {
                            Button(action: { watchSession.addToTimer(seconds: -15) }) {
                                Image(systemName: "minus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 38)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        // Play / Pause
                        if watchSession.timer == nil {
                            Button(action: { watchSession.startTimer() }) {
                                Image(systemName: "play.fill")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(width: 90, height: 38)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        } else if watchSession.timer?.isPaused == true {
                            Button(action: { watchSession.resumeTimer() }) {
                                Image(systemName: "play.fill")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(width: 90, height: 38)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Button(action: { watchSession.pauseTimer() }) {
                                Image(systemName: "pause.fill")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(width: 90, height: 38)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        if watchSession.timer == nil {
                            Button(action: { watchSession.addToTimer(seconds: 15) }) {
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 38)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    // Cancel only when running
                    if watchSession.timer != nil {
                        Button("Cancel") { watchSession.stopTimer(delete: true) }
                            .foregroundColor(.red)
                            .padding(.top, 2)
                    }
                }
            }
            .padding()
        }
    }

    // Computed
    private var timerDisplay: String {
        watchSession.timer == nil ? watchSession.formattedPending : watchSession.formatted
    }

    private var progress: CGFloat {
        guard let remaining = watchSession.remainingTime else { return 1 }
        let total = CGFloat(watchSession.timer?.timerLength ?? 1)
        return max(CGFloat(remaining) / total, 0)
    }
}
