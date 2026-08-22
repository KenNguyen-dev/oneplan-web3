//
//  CachedRemoteImage.swift
//  OnePlan
//

import SwiftUI
import UIKit

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let maxPixelSize: CGFloat?

    @State private var image: UIImage?
    @State private var resolvedURL: URL?

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        if let targetSize {
            let scale = UITraitCollection.current.displayScale
            let effectiveScale = scale > 0 ? scale : 3.0
            self.maxPixelSize = max(targetSize.width, targetSize.height) * effectiveScale
        } else {
            self.maxPixelSize = nil
        }
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let displayedImage {
                content(Image(uiImage: displayedImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            resolvedURL = nil
            image = nil
            return
        }

        if resolvedURL != url {
            resolvedURL = url
            image = TripImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixelSize)
        }

        guard image == nil else { return }
        let loadedImage = await TripImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled, resolvedURL == url else { return }
        image = loadedImage
    }

    private var displayedImage: UIImage? {
        if resolvedURL == url, let image {
            return image
        }
        guard let url else { return nil }
        return TripImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixelSize)
    }
}
