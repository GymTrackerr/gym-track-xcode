//
//  MediaCache.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-12.
//

import Foundation
import ImageIO

/// Handles downloading and caching of both images and GIFs.
actor MediaCache {
    static let shared = MediaCache()
    
    private let cacheDir: URL
    
    enum MediaCacheError: Error {
        case invalidHTTPStatus(Int)
        case invalidMediaContent
    }

    init() {
        cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// Returns the local cache path for a given remote URL.
    private func localPath(for url: URL) -> URL {
//        var fileKey: String
        
        // Use the full path instead of just lastPathComponent for uniqueness
        let encoded = url.path.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent(encoded)
    }

    /// Returns the cached file if it already exists.
    func cachedFile(for url: URL) -> URL? {
        let path = localPath(for: url)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Downloads and caches a media file (image or gif).
    /// If `forceRefresh` is false and the file already exists, it returns the local file path immediately.
    func fetch(_ url: URL, forceRefresh: Bool = false) async throws -> URL {
        let destination = localPath(for: url)

        if forceRefresh {
            if FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.removeItem(at: destination)
                    print("Force refresh removed cached file for \(url.absoluteString)")
                } catch {
                    print("Failed to remove cached file during force refresh for \(url.absoluteString): \(error)")
                }
            }
        } else if let existing = cachedFile(for: url) {
            if isValidImageFile(at: existing) {
                print("Using existing cache file \(existing) for \(url.absoluteString)")
                return existing
            } else {
                do {
                    try FileManager.default.removeItem(at: existing)
                    print("Removed invalid cached media file \(existing) for \(url.absoluteString)")
                } catch {
                    print("Failed removing invalid cached media file \(existing): \(error)")
                }
            }
        }

        // Otherwise download it
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            print("Media fetch bad status \(httpResponse.statusCode) for \(url.absoluteString)")
            throw MediaCacheError.invalidHTTPStatus(httpResponse.statusCode)
        }
        guard isValidImageData(data) else {
            if let body = String(data: data.prefix(120), encoding: .utf8) {
                print("Media fetch returned non-image payload for \(url.absoluteString): \(body)")
            } else {
                print("Media fetch returned non-image payload for \(url.absoluteString)")
            }
            throw MediaCacheError.invalidMediaContent
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Clears all cached media files
    func clearAll() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            print("Media cache cleared.")
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
    
    private func isValidImageData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
    
    private func isValidImageFile(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
