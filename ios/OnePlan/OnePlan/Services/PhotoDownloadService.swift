//
//  PhotoDownloadService.swift
//  OnePlan
//

import Foundation
import Photos
import UIKit

@MainActor
@Observable
final class PhotoDownloadService {
    enum DownloadResult {
        case success(savedCount: Int)
        case permissionDenied
        case failure(message: String)
    }

    var isDownloading = false
    var progress: Double = 0
    var completedCount = 0
    var totalCount = 0

    func downloadAllPhotos(photos: [TripPhotoDto]) async -> DownloadResult {
        guard !isDownloading else { return .failure(message: "Download already in progress.") }
        guard !photos.isEmpty else { return .failure(message: "No photos to download.") }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }

        isDownloading = true
        totalCount = photos.count
        completedCount = 0
        progress = 0
        defer { isDownloading = false }

        var savedCount = 0
        for photo in photos {
            guard let url = URL(string: photo.url) else { continue }
            var image: UIImage? = await TripImageCache.shared.image(for: url)
            if image == nil {
                image = try? await downloadImage(from: url)
            }
            if let image {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                    savedCount += 1
                } catch { /* continue with remaining photos */ }
            }
            completedCount += 1
            progress = Double(completedCount) / Double(totalCount)
        }
        return .success(savedCount: savedCount)
    }

    /// Saves a single in-memory image. Deliberately does not touch the
    /// isDownloading/progress state that drives the trip-photos progress UI.
    func saveImage(_ image: UIImage) async -> DownloadResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .success(savedCount: 1)
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    private func downloadImage(from url: URL) async throws -> UIImage? {
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)
    }
}
