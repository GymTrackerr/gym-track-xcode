//
//  MediaCache.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-12.
//

import Foundation

/// Handles downloading and caching of both images and GIFs.
actor MediaCache {
    static let shared = MediaCache()
    
    private let cacheDir: URL

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
    /// If it's already cached, it returns the local file path immediately.
    func fetch(_ url: URL) async throws -> URL {
        // If file already exists, return it.
        
        if let existing = cachedFile(for: url) {
            print("giving exisitng cache url \(existing), \(url)")
            return existing
        }

        // Otherwise download it
        let (data, _) = try await URLSession.shared.data(from: url)
        let destination = localPath(for: url)
        try data.write(to: destination)
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
}
