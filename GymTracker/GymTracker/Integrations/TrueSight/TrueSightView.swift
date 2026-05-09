//
//  TrueSightView.swift
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

// MARK: - SwiftUI Video Picker
struct TrueSightView: View {
    @StateObject private var manager = TrueSightManager()
    @EnvironmentObject var exerciseService: ExerciseService
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var selectedVideoFilename = ""
    @State private var selectedExerciseId: UUID?
    @State private var drawSkeleton = true
    @State private var showRecommendations = true
    @State private var isWebcamMode = false
    @State private var isPreparingVideo = false
    @State private var isCheckingExercise = false
    @State private var selectionErrorMessage: String?

    init(initialExerciseId: UUID? = nil) {
        _selectedExerciseId = State(initialValue: initialExerciseId)
    }

    private var selectableExercises: [Exercise] {
        exerciseService.exercises
            .filter { exercise in
                guard let npId = exercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !npId.isEmpty && !exercise.isArchived
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var selectedExercise: Exercise? {
        if let selectedExerciseId {
            return selectableExercises.first { $0.id == selectedExerciseId }
        }
        return nil
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Exercise Video Analysis")
                    .font(.title2)
                    .fontWeight(.bold)
                
                NavigationLink {
                    FitSightExercisePickerView(selectedExerciseId: $selectedExerciseId)
                } label: {
                    CardRowContainer {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Exercise")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(selectedExercise?.name ?? "Choose ExerciseDB-backed exercise")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Text(selectedExercise?.npId ?? "Uses local exercises that have an npId")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Select video button (only show if not in webcam mode)
                if !isWebcamMode {
                    Button(action: {
                        showVideoPicker = true
                    }) {
                        VStack(spacing: 6) {
                            Label("Select Video", systemImage: "video.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(
                                isPreparingVideo
                                    ? "Preparing video for upload…"
                                    : (selectedVideoFilename.isEmpty ? "Choose a local video file before uploading." : selectedVideoFilename)
                            )
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.86))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .disabled(manager.isProcessing || isPreparingVideo)
                }
                
                // Upload button
                if isWebcamMode || selectedVideoURL != nil {
                    Button(action: {
                        runPreUploadCheckThenUpload()
                    }) {
                        Label(isWebcamMode ? "Start Webcam Stream" : "Upload & Process", systemImage: isWebcamMode ? "camera.fill" : "icloud.and.arrow.up")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .disabled(manager.isProcessing || selectedExercise == nil || isPreparingVideo || isCheckingExercise)
                }

                if isCheckingExercise {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Checking exercise support...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Processing status
                if manager.isProcessing {
                    CardRowContainer {
                        VStack(spacing: 10) {
                        if manager.isUploading {
                            ProgressView(value: manager.uploadProgress) {
                                Text("Uploading video…")
                            } currentValueLabel: {
                                Text("\(Int((manager.uploadProgress * 100).rounded()))%")
                            }
                            .progressViewStyle(.linear)
                        } else {
                            ProgressView("Processing video…")
                                .progressViewStyle(.circular)
                        }

                        Text(manager.isUploading ? "Uploading the selected video to TrueSight." : "Upload finished. TrueSight is processing the video now.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        }
                    }
                }

                if let selectionErrorMessage {
                    Text(selectionErrorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Error message
                if let error = manager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
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
                    }
                }
                
                Spacer(minLength: 8)
            }
            .padding(.vertical, 12)
            .screenContentPadding()
        }
        .navigationTitle("TrueSight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedExerciseId == nil {
                selectedExerciseId = selectableExercises.first?.id
            }
        }
        .onChange(of: selectableExercises.map(\.id)) {
            guard let firstExercise = selectableExercises.first else {
                selectedExerciseId = nil
                return
            }
            if let selectedExerciseId,
               selectableExercises.contains(where: { $0.id == selectedExerciseId }) {
                return
            }
            self.selectedExerciseId = firstExercise.id
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(
                selectedVideoURL: $selectedVideoURL,
                selectedFilename: $selectedVideoFilename,
                isPreparingVideo: $isPreparingVideo,
                errorMessage: $selectionErrorMessage
            )
        }
    }

    private func runPreUploadCheckThenUpload() {
        guard let videoURL = selectedVideoURL, let selectedExercise else { return }
        let npId = selectedExercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines)

        selectionErrorMessage = nil
        isCheckingExercise = true

        Task {
            do {
                try await manager.verifyExerciseSupport(
                    exerciseName: selectedExercise.name,
                    npId: npId
                )

                await MainActor.run {
                    isCheckingExercise = false
                    manager.uploadVideo(
                        videoURL: videoURL,
                        exercise: selectedExercise.name,
                        drawSkeleton: drawSkeleton,
                        recommend: showRecommendations,
                        isWebcam: isWebcamMode
                    )
                }
            } catch {
                await MainActor.run {
                    isCheckingExercise = false
                    selectionErrorMessage = error.localizedDescription
                }
            }
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

struct FitSightExercisePickerView: View {
    @EnvironmentObject var exerciseService: ExerciseService
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedExerciseId: UUID?
    @State private var searchText = ""

    private var selectableExercises: [Exercise] {
        exerciseService.exercises
            .filter { exercise in
                guard let npId = exercise.npId?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !npId.isEmpty && !exercise.isArchived
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var filteredExercises: [Exercise] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return selectableExercises
        }

        let normalized = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return selectableExercises.filter { exercise in
            exercise.name.localizedCaseInsensitiveContains(normalized)
            || (exercise.npId?.localizedCaseInsensitiveContains(normalized) ?? false)
            || (exercise.aliases ?? []).contains(where: { $0.localizedCaseInsensitiveContains(normalized) })
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredExercises, id: \.id) { exercise in
                    Button {
                        selectedExerciseId = exercise.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            SingleExerciseLabelView(exercise: exercise)
                            Spacer()
                            if selectedExerciseId == exercise.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Only exercises with a valid npId are shown here, so the selection stays aligned with the ExerciseDB-backed TrueSight flow.")
            }
        }
        .screenContentPadding()
        .navigationTitle("Choose Exercise")
        .searchable(text: $searchText, prompt: "Search exercises or npId")
    }
}

// MARK: - Video Picker (UIKit Bridge)
struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    @Binding var selectedFilename: String
    @Binding var isPreparingVideo: Bool
    @Binding var errorMessage: String?
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
                DispatchQueue.main.async {
                    self.parent.errorMessage = nil
                    self.parent.isPreparingVideo = true
                }
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url = url else {
                        DispatchQueue.main.async {
                            self.parent.isPreparingVideo = false
                            self.parent.errorMessage = error?.localizedDescription ?? "Could not access the selected video."
                        }
                        return
                    }

                    let workingURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("picked_video_\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")

                    do {
                        try? FileManager.default.removeItem(at: workingURL)
                        try FileManager.default.copyItem(at: url, to: workingURL)
                    } catch {
                        DispatchQueue.main.async {
                            self.parent.isPreparingVideo = false
                            self.parent.errorMessage = "Could not copy selected video: \(error.localizedDescription)"
                        }
                        return
                    }

                    normalizeVideoForUpload(inputURL: workingURL) { result in
                        DispatchQueue.main.async {
                            self.parent.isPreparingVideo = false

                            switch result {
                            case .success(let preparedURL):
                                self.parent.selectedVideoURL = preparedURL
                                self.parent.selectedFilename = url.lastPathComponent
                                self.parent.errorMessage = nil

                            case .failure(let error):
                                self.parent.errorMessage = "Could not prepare video: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
    }
}

private func normalizeVideoForUpload(
    inputURL: URL,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    let asset = AVURLAsset(url: inputURL)
    Task {
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                completion(.failure(NSError(domain: "FitSightVideoPreparation", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Selected file did not contain a video track."
                ])))
                return
            }

            let assetDuration = try await asset.load(.duration)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let naturalSize = try await videoTrack.load(.naturalSize)

            let composition = AVMutableComposition()
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                completion(.failure(NSError(domain: "FitSightVideoPreparation", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create video composition track."
                ])))
                return
            }

            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: videoTrack,
                at: .zero
            )

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks.first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: assetDuration),
                    of: audioTrack,
                    at: .zero
                )
            }

            let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let renderSize = CGSize(
                width: abs(transformedRect.width),
                height: abs(transformedRect.height)
            )
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let fps: Int32 = nominalFrameRate > 0 ? Int32(nominalFrameRate.rounded()) : 30
            let frameDuration = CMTime(value: 1, timescale: fps)

            // Re-anchor the transformed frame into a positive render space.
            // Some iPhone rotations include negative translation components.
            let correctedTransform = preferredTransform.concatenating(
                CGAffineTransform(
                    translationX: -transformedRect.origin.x,
                    y: -transformedRect.origin.y
                )
            )

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("prepared_video_\(Date().timeIntervalSince1970).mp4")

            try? FileManager.default.removeItem(at: outputURL)

            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                completion(.failure(NSError(domain: "FitSightVideoPreparation", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create export session."
                ])))
                return
            }

            exportSession.shouldOptimizeForNetworkUse = true
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(correctedTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = [instruction]
            videoComposition.frameDuration = frameDuration
            videoComposition.renderSize = renderSize
            exportSession.videoComposition = videoComposition
            try await exportSession.export(to: outputURL, as: .mp4)
            completion(.success(outputURL))
        } catch {
            completion(.failure(error))
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
