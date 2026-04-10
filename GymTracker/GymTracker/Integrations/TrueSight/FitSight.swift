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
class FitSightManager: NSObject, ObservableObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    struct UploadResponse: Decodable {
        let status: String?
        let message: String?
        let requestId: String?
        let processed: Bool?
        let outputPath: String?
        let videoURL: String?

        enum CodingKeys: String, CodingKey {
            case status
            case message
            case requestId = "request_id"
            case processed
            case outputPath = "output_path"
            case videoURL = "video_url"
        }
    }

    struct StatusResponse: Decodable {
        let status: String
        let message: String?
        let requestId: String?
        let outputPath: String?
        let videoURL: String?

        enum CodingKeys: String, CodingKey {
            case status
            case message
            case requestId = "request_id"
            case outputPath = "output_path"
            case videoURL = "video_url"
        }
    }

    @Published var isProcessing = false
    @Published var isUploading = false
    @Published var processedVideoURL: URL?
    @Published var errorMessage: String?
    @Published var uploadProgress: Double = 0.0
    
    private let baseURL = "https://api.trackerr.ca/truesight"
    private var pollingTimer: Timer?
    private var activeRequestId: String?
    private var uploadResponseData = Data()
    private var uploadCompletion: ((Result<Data, Error>) -> Void)?
    
    // Upload video to FitSight API
    func uploadVideo(videoURL: URL, exercise: String, drawSkeleton: Bool = true, recommend: Bool = true, isWebcam: Bool = false) {
        isProcessing = true
        isUploading = true
        errorMessage = nil
        uploadProgress = 0.0
        processedVideoURL = nil
        activeRequestId = nil
        
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
        body.append("\(drawSkeleton ? "true" : "false")\r\n".data(using: .utf8)!)
        
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
        
        uploadResponseData = Data()
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.uploadTask(with: request, from: body)
        uploadCompletion = { [weak self] result in
            DispatchQueue.main.async {
                self?.isUploading = false

                switch result {
                case .failure(let error):
                    self?.errorMessage = "Upload failed: \(error.localizedDescription)"
                    self?.isProcessing = false

                case .success(let data):
                    guard let self else { return }

                    do {
                        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)

                        if decoded.processed == true,
                           let resolvedURL = self.resolveOutputURL(relativeOrAbsolutePath: decoded.videoURL ?? decoded.outputPath) {
                            self.processedVideoURL = resolvedURL
                            self.isProcessing = false
                            self.uploadProgress = 1.0
                            return
                        }

                        guard let requestId = decoded.requestId, !requestId.isEmpty else {
                            self.errorMessage = decoded.message ?? "Upload succeeded but no processing request id was returned."
                            self.isProcessing = false
                            return
                        }

                        self.activeRequestId = requestId
                        self.uploadProgress = 1.0
                        self.startPollingStatus(requestId: requestId)
                    } catch {
                        self.errorMessage = "Upload response could not be decoded."
                        self.isProcessing = false
                    }
                }
            }
        }

        task.resume()
    }
    
    // Poll processing status
    private func startPollingStatus(requestId: String) {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkProcessingStatus(requestId: requestId)
        }
    }
    
    private func checkProcessingStatus(requestId: String) {
        let encodedRequestId = requestId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? requestId
        guard let url = URL(string: "\(baseURL)/api/status/\(encodedRequestId)") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data else { return }
            guard let statusResponse = try? JSONDecoder().decode(StatusResponse.self, from: data) else { return }
            
            DispatchQueue.main.async {
                if statusResponse.status == "complete" {
                    self?.pollingTimer?.invalidate()
                    self?.activeRequestId = nil
                    self?.processedVideoURL = self?.resolveOutputURL(
                        relativeOrAbsolutePath: statusResponse.videoURL ?? statusResponse.outputPath
                    )
                    self?.isProcessing = false
                }
            }
        }.resume()
    }

    private func resolveOutputURL(relativeOrAbsolutePath: String?) -> URL? {
        guard let relativeOrAbsolutePath, !relativeOrAbsolutePath.isEmpty else { return nil }
        if let absoluteURL = URL(string: relativeOrAbsolutePath), absoluteURL.scheme != nil {
            return absoluteURL
        }

        if relativeOrAbsolutePath.hasPrefix("/") {
            return URL(string: "\(baseURL)\(relativeOrAbsolutePath)")
        }

        return URL(string: "\(baseURL)/\(relativeOrAbsolutePath)")
    }
    
    deinit {
        pollingTimer?.invalidate()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        uploadResponseData.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.uploadProgress = min(max(progress, 0), 1)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let completion = uploadCompletion
        uploadCompletion = nil

        if let error {
            completion?(.failure(error))
        } else {
            completion?(.success(uploadResponseData))
        }

        uploadResponseData = Data()
        session.finishTasksAndInvalidate()
    }
}

// MARK: - SwiftUI Video Picker
struct FitSightView: View {
    @StateObject private var manager = FitSightManager()
    @EnvironmentObject var exerciseService: ExerciseService
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var selectedVideoFilename = ""
    @State private var selectedExerciseId: UUID?
    @State private var drawSkeleton = true
    @State private var showRecommendations = true
    @State private var isWebcamMode = false
    @State private var isPreparingVideo = false
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
                    .padding(.horizontal, 16)
                
                NavigationLink {
                    FitSightExercisePickerView(selectedExerciseId: $selectedExerciseId)
                } label: {
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
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 16)

                // Options
                /*
                Toggle("Draw Skeleton", isOn: $drawSkeleton)
                    .padding(.horizontal, 16)
                Toggle("Show Recommendations", isOn: $showRecommendations)
                    .padding(.horizontal, 16)
                Toggle("Webcam Mode", isOn: $isWebcamMode)
                    .padding(.horizontal, 16)
                */
                
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
                    .padding(.horizontal, 16)
                    .disabled(manager.isProcessing || isPreparingVideo)
                }
                
                // Upload button
                if isWebcamMode || selectedVideoURL != nil {
                    Button(action: {
                        if let videoURL = selectedVideoURL,
                           let selectedExercise {
                            manager.uploadVideo(
                                videoURL: videoURL,
                                exercise: selectedExercise.name,
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
                    .padding(.horizontal, 16)
                    .disabled(manager.isProcessing || selectedExercise == nil || isPreparingVideo)
                }
                
                // Processing status
                if manager.isProcessing {
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
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                if let selectionErrorMessage {
                    Text(selectionErrorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                }
                
                // Error message
                if let error = manager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
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
                            .padding(.horizontal, 16)
                        
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
                        .padding(.horizontal, 16)
                    }
                }
                
                Spacer(minLength: 8)
            }
            .padding(.vertical, 12)
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

                    normalizeVideoForUpload(inputURL: url) { result in
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

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        completion(.failure(NSError(domain: "FitSightVideoPreparation", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Selected file did not contain a video track."
        ])))
        return
    }

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

    do {
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.duration),
            of: videoTrack,
            at: .zero
        )

        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: audioTrack,
                at: .zero
            )
        }
    } catch {
        completion(.failure(error))
        return
    }

    let preferredTransform = videoTrack.preferredTransform
    let transformedSize = videoTrack.naturalSize.applying(preferredTransform)
    let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
    layerInstruction.setTransform(preferredTransform, at: .zero)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.instructions = [instruction]
    let nominalFrameRate = videoTrack.nominalFrameRate
    let fps: Int32 = nominalFrameRate > 0 ? Int32(nominalFrameRate.rounded()) : 30
    videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
    videoComposition.renderSize = renderSize

    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("prepared_video_\(Date().timeIntervalSince1970).mp4")

    try? FileManager.default.removeItem(at: outputURL)

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        completion(.failure(NSError(domain: "FitSightVideoPreparation", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Could not create export session."
        ])))
        return
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition

    exportSession.exportAsynchronously {
        switch exportSession.status {
        case .completed:
            completion(.success(outputURL))
        case .failed, .cancelled:
            completion(.failure(exportSession.error ?? NSError(
                domain: "FitSightVideoPreparation",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Video export failed."]
            )))
        default:
            break
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
