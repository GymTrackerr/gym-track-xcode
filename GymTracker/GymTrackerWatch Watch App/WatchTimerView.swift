//
//  WatchTimerView.swift
//  GymTrackerWatch Watch App
//
//  Created by Daniel Kravec on 2025-12-07.
//

import SwiftUI

struct WatchTimerView: View {
    @EnvironmentObject var timerModel: WatchTimerExtensionModel

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
                        
                        if timerModel.hasActiveTimer {
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
                    if !timerModel.hasActiveTimer {
                        Button(action: { timerModel.addToTimer(seconds: 15) }) {
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
                        
                        if !timerModel.hasActiveTimer {
                            Button(action: { timerModel.addToTimer(seconds: -15) }) {
                                Image(systemName: "minus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 38)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        // Play / Pause
                        if !timerModel.hasActiveTimer {
                            Button(action: { timerModel.startTimer() }) {
                                Image(systemName: "play.fill")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(width: 90, height: 38)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        } else if timerModel.isPaused {
                            Button(action: { timerModel.resumeTimer() }) {
                                Image(systemName: "play.fill")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(width: 90, height: 38)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Button(action: { timerModel.pauseTimer() }) {
                                Image(systemName: "pause.fill")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(width: 90, height: 38)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        if !timerModel.hasActiveTimer {
                            Button(action: { timerModel.addToTimer(seconds: 15) }) {
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
                    if timerModel.hasActiveTimer {
                        Button("Cancel") { timerModel.stopTimer(delete: true) }
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
        timerModel.timerDisplayText
    }

    private var progress: CGFloat {
        CGFloat(max(timerModel.progress, 0))
    }
}
