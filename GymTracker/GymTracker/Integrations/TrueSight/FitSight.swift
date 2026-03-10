//
//  FitSight.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-01-27.
//

import SwiftUI
import Combine
import Foundation
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

// MARK: - FitSight API Manager
class FitSightManager: ObservableObject {
    @Published var isProcessing = false
    @Published var processedVideoURL: URL?
    @Published var errorMessage: String?
    @Published var uploadProgress: Double = 0.0
    
    private let baseURL = "http://192.168.3.20:3000"
    private var pollingTimer: Timer?
    
    // Upload video to FitSight API
    func uploadVideo(videoURL: URL, exercise: String, drawSkeleton: Bool = true, recommend: Bool = true, isWebcam: Bool = false) {
        isProcessing = true
        errorMessage = nil
        uploadProgress = 0.0
        processedVideoURL = nil
        
        let url = URL(string: "\(baseURL)/upload")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 900.0) // 15 minute timeout for large videos
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add form fields
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"exercise\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(exercise)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"webcamstream\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isWebcam ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"drawSkeleton\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(drawSkeleton ? "yes" : "no")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"recommend\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(recommend ? "yes" : "no")\r\n".data(using: .utf8)!)
        
        // Add video file
        if let videoData = try? Data(contentsOf: videoURL) {
            let filename = videoURL.lastPathComponent
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Upload failed: \(error.localizedDescription)"
                    self?.isProcessing = false
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    self?.isProcessing = false
                    return
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let processed = json["processed"] as? Bool, processed,
                   let videoURLString = json["video_url"] as? String {
                    // Video processed immediately
                    self?.processedVideoURL = URL(string: "\(self?.baseURL ?? "")\(videoURLString)")
                    self?.isProcessing = false
                } else {
                    // Start polling for status
                    self?.startPollingStatus()
                }
            }
        }
        
        task.resume()
    }
    
    // Poll processing status
    private func startPollingStatus() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkProcessingStatus()
        }
    }
    
    private func checkProcessingStatus() {
        let url = URL(string: "\(baseURL)/check_processing_status")!
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else { return }
            
            DispatchQueue.main.async {
                if status == "complete" {
                    self?.pollingTimer?.invalidate()
                    if let videoURLString = json["video_url"] as? String {
                        self?.processedVideoURL = URL(string: "\(self?.baseURL ?? "")\(videoURLString)")
                        self?.isProcessing = false
                    }
                }
            }
        }.resume()
    }
    
    deinit {
        pollingTimer?.invalidate()
    }
}

// MARK: - SwiftUI Video Picker
struct FitSightView: View {
    @StateObject private var manager = FitSightManager()
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var exerciseName = ""
    @State private var drawSkeleton = true
    @State private var showRecommendations = true
    @State private var isWebcamMode = false
    
    private let exercises = [
        ("", "Select Exercise"),
        ("bicep", "Bicep Curl"),
        ("squats", "Squats"),
        ("shoulder_lateral_raise", "Shoulder Lateral Raise"),
        ("bent_over_row", "Bent Over Row"),
        ("lunges", "Lunges"),
        ("shoulder_press", "Shoulder Press"),
        ("pushup", "Pushups")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("FitSight Video Analysis")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Exercise dropdown
            HStack {
                Text("Exercise:")
                    .fontWeight(.semibold)
                Picker("Exercise", selection: $exerciseName) {
                    ForEach(exercises, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            
            // Options
            Toggle("Draw Skeleton", isOn: $drawSkeleton)
                .padding(.horizontal)
            Toggle("Show Recommendations", isOn: $showRecommendations)
                .padding(.horizontal)
            Toggle("Webcam Mode", isOn: $isWebcamMode)
                .padding(.horizontal)
            
            // Select video button (only show if not in webcam mode)
            if !isWebcamMode {
                Button(action: {
                    showVideoPicker = true
                }) {
                    Label("Select Video", systemImage: "video.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(manager.isProcessing)
            }
            
            // Upload button
            if isWebcamMode || selectedVideoURL != nil {
                Button(action: {
                    if let videoURL = selectedVideoURL {
                        manager.uploadVideo(
                            videoURL: videoURL,
                            exercise: exerciseName,
                            drawSkeleton: drawSkeleton,
                            recommend: showRecommendations,
                            isWebcam: isWebcamMode
                        )
                    }
                }) {
                    Label(isWebcamMode ? "Start Webcam Stream" : "Upload & Process", systemImage: isWebcamMode ? "camera.fill" : "icloud.and.arrow.up")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(manager.isProcessing || exerciseName.isEmpty)
            }
            
            // Processing status
            if manager.isProcessing {
                VStack(spacing: 10) {
                    ProgressView("Processing video...")
                        .progressViewStyle(.circular)
                    Text("This may take a few minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Error message
            if let error = manager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            // Processed video
            if let processedURL = manager.processedVideoURL {
                VStack(spacing: 15) {
                    Text("✓ Processing Complete!")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    ProcessedVideoPlayer(url: processedURL)
                        .frame(height: 300)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    
                    Button(action: {
                        downloadVideo(url: processedURL)
                    }) {
                        Label("Download Video", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.purple)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(selectedVideoURL: $selectedVideoURL)
        }
    }
    
    private func downloadVideo(url: URL) {
        // Download and save to photo library
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else { return }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("processed_video_\(Date().timeIntervalSince1970).mp4")
            try? data.write(to: tempURL)
            
            // Save to photo library
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to photo library")
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Video Picker (UIKit Bridge)
struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url = url else { return }
                    
                    // Copy to temp directory to ensure access
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("selected_video_\(Date().timeIntervalSince1970).mp4")
                    try? FileManager.default.copyItem(at: url, to: tempURL)
                    
                    DispatchQueue.main.async {
                        self.parent.selectedVideoURL = tempURL
                    }
                }
            }
        }
    }
}

// MARK: - Processed Video Player
struct ProcessedVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player = AVPlayer(url: url)
                player?.play()
            }
            .onDisappear {
                player?.pause()
            }
    }
}

