//
//  TrueSightManager.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-04-10.
//

import SwiftUI
import Combine
import Foundation
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

class TrueSightManager: NSObject, ObservableObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    struct AnalyzeRequest: Encodable {
        let exerciseName: String
        let exerciseId: String?
        let images: [String]

        enum CodingKeys: String, CodingKey {
            case exerciseName = "exercise_name"
            case exerciseId = "exercise_id"
            case images
        }
    }

    struct AnalyzeResponse: Decodable {
        let status: String?
        let message: String?
    }

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
    private var uploadBodyFileURL: URL?

    // Lightweight pre-upload check: mirrors TrueSight web "analyze" call.
    func verifyExerciseSupport(exerciseName: String, npId: String?) async throws {
        guard let url = URL(string: "\(baseURL)/api/analyze") else {
            throw NSError(domain: "FitSight", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid analyze URL"])
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AnalyzeRequest(
            exerciseName: exerciseName,
            exerciseId: npId,
            images: []
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "FitSight", code: 2, userInfo: [NSLocalizedDescriptionKey: "No response from TrueSight"])
        }

        if (200..<300).contains(http.statusCode) {
            return
        }

        if let decoded = try? JSONDecoder().decode(AnalyzeResponse.self, from: data),
           let message = decoded.message, !message.isEmpty {
            throw NSError(domain: "FitSight", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        throw NSError(domain: "FitSight", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Exercise is not supported by TrueSight."])
    }
    
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
        
        let bodyFileURL: URL
        do {
            bodyFileURL = try createMultipartUploadFile(
                videoURL: videoURL,
                boundary: boundary,
                exercise: exercise,
                drawSkeleton: drawSkeleton,
                recommend: recommend,
                isWebcam: isWebcam
            )
            uploadBodyFileURL = bodyFileURL
        } catch {
            isUploading = false
            isProcessing = false
            errorMessage = "Upload preparation failed: \(error.localizedDescription)"
            return
        }
        
        uploadResponseData = Data()
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.uploadTask(with: request, fromFile: bodyFileURL)
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

    private func createMultipartUploadFile(
        videoURL: URL,
        boundary: String,
        exercise: String,
        drawSkeleton: Bool,
        recommend: Bool,
        isWebcam: Bool
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fitsight_upload_\(UUID().uuidString).multipart")

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let writer = try FileHandle(forWritingTo: outputURL)
        defer { try? writer.close() }

        func writeString(_ value: String) throws {
            try writer.write(contentsOf: Data(value.utf8))
        }

        func writeField(name: String, value: String) throws {
            try writeString("--\(boundary)\r\n")
            try writeString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try writeString("\(value)\r\n")
        }

        try writeField(name: "exercise", value: exercise)
        try writeField(name: "webcamstream", value: isWebcam ? "true" : "false")
        try writeField(name: "drawSkeleton", value: drawSkeleton ? "true" : "false")
        try writeField(name: "recommend", value: recommend ? "yes" : "no")

        let filename = videoURL.lastPathComponent
        try writeString("--\(boundary)\r\n")
        try writeString("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n")
        try writeString("Content-Type: video/mp4\r\n\r\n")

        let reader = try FileHandle(forReadingFrom: videoURL)
        defer { try? reader.close() }
        while true {
            let chunk = try reader.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
        }
        try writeString("\r\n")
        try writeString("--\(boundary)--\r\n")

        return outputURL
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

        if let uploadBodyFileURL {
            try? FileManager.default.removeItem(at: uploadBodyFileURL)
            self.uploadBodyFileURL = nil
        }
        uploadResponseData = Data()
        session.finishTasksAndInvalidate()
    }
}
