//
//  TripImageCache.swift
//  OnePlan
//

import CryptoKit
import Foundation
import ImageIO
import UIKit

final class TripImageCache {
    static let shared = TripImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let cacheDirectory: URL
    private let maxDiskAge: TimeInterval
    private let lock = NSLock()
    private var inFlightTasks: [String: Task<Data?, Never>] = [:]

    init(maxDiskAge: TimeInterval = 7 * 24 * 60 * 60) {
        let baseDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        self.cacheDirectory = baseDirectory.appendingPathComponent(
            "trip-image-cache",
            isDirectory: true
        )
        self.maxDiskAge = maxDiskAge
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    }

    func image(for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let key = cacheKey(for: url)
        let memKey = memoryCacheKey(base: key, maxPixelSize: maxPixelSize)

        if let cached = memoryCache.object(forKey: memKey) {
            return cached
        }

        if let cachedData = await loadValidDiskData(forKey: key) {
            let cachedImage: UIImage? = if let maxPixelSize {
                downsample(data: cachedData, maxPixelSize: maxPixelSize)
            } else {
                UIImage(data: cachedData)
            }
            if let cachedImage {
                memoryCache.setObject(cachedImage, forKey: memKey, cost: imageCost(cachedImage))
                return cachedImage
            }
            await removeDiskData(forKey: key)
        }

        let (task, isOwner) = getOrCreateFetchTask(for: url, key: key)
        if isOwner {
            defer { removeInFlightTask(forKey: key) }
        }

        guard let data = await task.value else { return nil }

        let image: UIImage? = if let maxPixelSize {
            downsample(data: data, maxPixelSize: maxPixelSize)
        } else {
            UIImage(data: data)
        }
        guard let image else { return nil }

        memoryCache.setObject(image, forKey: memKey, cost: imageCost(image))

        if isOwner {
            await writeDiskData(data, forKey: key)
        }

        return image
    }

    func cachedImage(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
        let key = cacheKey(for: url)
        let memKey = memoryCacheKey(base: key, maxPixelSize: maxPixelSize)
        return memoryCache.object(forKey: memKey)
    }

    func clearExpired() async {
        let directory = cacheDirectory
        let maxAge = maxDiskAge

        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            let now = Date()
            for file in files {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modifiedAt = values?.contentModificationDate else { continue }
                if now.timeIntervalSince(modifiedAt) > maxAge {
                    try? fileManager.removeItem(at: file)
                }
            }
        }.value
    }

    func clearAll() async {
        memoryCache.removeAllObjects()

        lock.lock()
        let tasks = inFlightTasks.values
        inFlightTasks.removeAll()
        lock.unlock()

        tasks.forEach { $0.cancel() }

        let directory = cacheDirectory
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: directory)
        }.value
    }

    private func memoryCacheKey(base: String, maxPixelSize: CGFloat?) -> NSString {
        if let maxPixelSize {
            return "\(base)_\(Int(maxPixelSize))" as NSString
        }
        return base as NSString
    }

    private func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func cacheKey(for url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }

        // Signed download URLs usually vary by query token while pointing to the same object.
        // Normalize key to host+path so re-issued signatures hit the same local cache entry.
        components.query = nil
        components.fragment = nil

        return components.url?.absoluteString ?? url.absoluteString
    }

    private func filename(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).img"
    }

    private func fileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(filename(for: key), isDirectory: false)
    }

    private func getOrCreateFetchTask(for url: URL, key: String) -> (Task<Data?, Never>, Bool) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = inFlightTasks[key] {
            return (existing, false)
        }

        let task = Task<Data?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                    !(200 ... 299).contains(httpResponse.statusCode)
                {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
        inFlightTasks[key] = task
        return (task, true)
    }

    private func removeInFlightTask(forKey key: String) {
        lock.lock()
        inFlightTasks.removeValue(forKey: key)
        lock.unlock()
    }

    private func loadValidDiskData(forKey key: String) async -> Data? {
        let fileURL = fileURL(for: key)
        let maxAge = maxDiskAge

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

            do {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let modifiedAt = attributes[.modificationDate] as? Date,
                    Date().timeIntervalSince(modifiedAt) > maxAge
                {
                    try? fileManager.removeItem(at: fileURL)
                    return nil
                }

                return try Data(contentsOf: fileURL)
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }.value
    }

    private func writeDiskData(_ data: Data, forKey key: String) async {
        let directory = cacheDirectory
        let fileURL = fileURL(for: key)

        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                // `.completeFileProtectionUntilFirstUserAuthentication` keeps
                // the cache readable for background work after the first
                // unlock while encrypting it at rest before that. Cached trip
                // imagery can include identifying photos, so unprotected
                // storage would be readable on a jailbroken / forensically
                // imaged device.
                try data.write(
                    to: fileURL,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            } catch {
                return
            }
        }.value
    }

    private func removeDiskData(forKey key: String) async {
        let fileURL = fileURL(for: key)
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: fileURL)
        }.value
    }
}
