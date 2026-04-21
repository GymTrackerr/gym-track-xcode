//
//  CacheMediaView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-12.
//

import SwiftUI
import WebKit

/// A unified SwiftUI view for displaying cached images or GIFs using MediaCache.
struct CachedMediaView: View {
    let url: URL
    @State private var localFile: URL?
    @State private var image: UIImage?
    @State private var isGIF = false
    @State private var failed = false

    var body: some View {
        Group {
            if let localFile, isGIF {
                AnimatedGIFView(fileURL: localFile)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            } else {
                ProgressView()
                    .task { await loadMedia() }
            }
        }
    }

    @MainActor
    private func loadMedia() async {
        do {
            let fileURL = try await MediaCache.shared.fetch(url)
            localFile = fileURL
            isGIF = fileURL.pathExtension.lowercased() == "gif"
            if !isGIF {
                image = UIImage(contentsOfFile: fileURL.path)
            }
        } catch {
            failed = true
            print("❌ Failed to load media: \(error)")
        }
    }
}

struct CachedThumbnailView: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.14))

                    Image(systemName: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: url) {
            await loadCachedThumbnail()
        }
    }

    @MainActor
    private func loadCachedThumbnail() async {
        image = nil

        var resolvedFile = await MediaCache.shared.cachedFile(for: url)
        if resolvedFile == nil {
            resolvedFile = try? await MediaCache.shared.fetch(url)
        }

        guard let cachedFile = resolvedFile else { return }
        image = UIImage(contentsOfFile: cachedFile.path)
    }
}

///// WebView-based GIF renderer for CachedMediaView.
//struct GIFWebView: UIViewRepresentable {
//    let fileURL: URL
//
//    func makeUIView(context: Context) -> WKWebView {
//        let webView = WKWebView()
//        webView.scrollView.isScrollEnabled = false
//        webView.isUserInteractionEnabled = false
//        webView.backgroundColor = .clear
//
//        print(fileURL)
//        
//        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileURL.lastPathComponent)
//        try? FileManager.default.copyItem(at: fileURL, to: tmpURL)
//
//        webView.loadFileURL(tmpURL, allowingReadAccessTo: tmpURL.deletingLastPathComponent())
//
//        // Read the GIF as data and load it directly.
////        if let data = try? Data(contentsOf: fileURL) {
////            webView.load(
////                data,
////                mimeType: "image/gif",
////                characterEncodingName: "utf-8",
////                baseURL: fileURL.deletingLastPathComponent()
////            )
////        } else {
////            print("⚠️ GIF data could not be read at \(fileURL)")
////        }
//
//        return webView
//    }
//
//    func updateUIView(_ uiView: WKWebView, context: Context) {}
//}

import ImageIO
import UIKit
import ImageIO

func isAnimatedGIF(at url: URL) -> Bool {
    guard
        url.pathExtension.lowercased() == "gif",
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)
    else { return false }

    let frameCount = CGImageSourceGetCount(src)
    return frameCount > 1
}


struct AnimatedGIFView: View {
    let fileURL: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .task { await loadGIF() }
            }
        }
    }

    private func loadGIF() async {
        guard let data = try? Data(contentsOf: fileURL),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return }

//        let url = URL(fileURLWithPath: fileURL)

        if isAnimatedGIF(at: fileURL) {
            print("🎞️ Animated GIF with multiple frames!")
        } else {
            print("🖼️ Static image (not animated)")
        }
        
        let count = CGImageSourceGetCount(src)
        var images: [UIImage] = []
        var duration: Double = 0

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gifDict?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gifDict?[kCGImagePropertyGIFDelayTime] as? Double
                ?? 0.1
            duration += delay
            images.append(UIImage(cgImage: cg))
        }

        image = UIImage.animatedImage(with: images, duration: duration)
    }
}
