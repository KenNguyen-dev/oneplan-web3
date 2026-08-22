//
//  TripPhotoSection.swift
//  OnePlan
//

import PhotosUI
import SwiftUI

struct TripPhotoSection: View {
    private enum Metrics {
        static let nonPremiumPhotoLimit = 5
        static let premiumPhotoSelectionLimit = 10
        static let columnCount = 3
        static let baseRowCount = 3

        static let boardWidth: CGFloat = .infinity
        static let boardHeight: CGFloat = 305
        static let rowStep: CGFloat = 97

        static let dotSize: CGFloat = 7
        static let dotTop: CGFloat = 59
        static let dotLeadingByColumn: [CGFloat] = [84, 181, 278]

        static let cardTop: CGFloat = 28.5
        static let cardSize = CGSize(width: 61, height: 75)
        static let cardCornerRadius: CGFloat = 11
        static let cardLeadingByColumn: [CGFloat] = [53.5, 154, 251]

        static let boardCornerRadius: CGFloat = 24
    }

    let photos: [TripPhotoDto]
    let isLoading: Bool
    let hasMore: Bool
    let isUploading: Bool
    let uploadProgress: Double
    let onLoadMore: () -> Void
    let onPhotoTapped: () -> Void
    let onPhotosSelected: ([PhotosPickerItem]) -> Void

    @Environment(StoreManager.self) private var storeManager
    @State private var showingPhotoPaywall = false
    @State private var selectedItems: [PhotosPickerItem] = []

    private var remainingPhotoSlots: Int? {
        guard !storeManager.isPro else { return nil }
        return max(0, Metrics.nonPremiumPhotoLimit - photos.count)
    }

    private var canUploadPhotos: Bool {
        storeManager.isPro || (remainingPhotoSlots ?? 0) > 0
    }

    private var maxPhotoSelectionCount: Int? {
        if storeManager.isPro {
            return Metrics.premiumPhotoSelectionLimit
        }
        return remainingPhotoSlots
    }

    private var photoRowCount: Int {
        max(1, (photos.count + Metrics.columnCount - 1) / Metrics.columnCount)
    }

    private var visibleRowCount: Int {
        max(Metrics.baseRowCount, photoRowCount)
    }

    private var boardHeight: CGFloat {
        Metrics.boardHeight + CGFloat(max(0, visibleRowCount - Metrics.baseRowCount)) * Metrics.rowStep
    }

    var body: some View {
        VStack(spacing: 16) {
            photoBoard
                .onTapGesture {
                    onPhotoTapped()
                }

            if canUploadPhotos {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: maxPhotoSelectionCount,
                    matching: .images
                ) {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }

                        Text(isUploading ? "Uploading..." : "Upload")
                    }
                    .fontWeight(.bold)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                }
                .disabled(isUploading)
                .background(Color(UIColor(red: 0.28, green: 0.73, blue: 1, alpha: 1)))
                .foregroundStyle(.white)
                .clipShape(.capsule)
                .opacity(isUploading ? 0.7 : 1)
                .padding(.horizontal, 2)
            } else {
                Button {
                    showingPhotoPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Upload")
                    }
                    .fontWeight(.bold)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                }
                .background(Color(UIColor(red: 0.28, green: 0.73, blue: 1, alpha: 1)))
                .foregroundStyle(.white)
                .clipShape(.capsule)
                .opacity(0.6)
                .padding(.horizontal, 2)
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }

            let acceptedItems: [PhotosPickerItem]
            if let maxPhotoSelectionCount {
                acceptedItems = Array(newItems.prefix(maxPhotoSelectionCount))
            } else {
                acceptedItems = newItems
            }

            guard !acceptedItems.isEmpty else {
                selectedItems = []
                showingPhotoPaywall = true
                return
            }

            onPhotosSelected(acceptedItems)
            selectedItems = []
        }
        .sheet(isPresented: $showingPhotoPaywall) {
            SubscriptionView()
        }
    }

    private var photoBoard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Metrics.boardCornerRadius, style: .continuous)
                .fill(Constants.Surface)

            ForEach(0..<visibleRowCount, id: \.self) { row in
                ForEach(0..<Metrics.columnCount, id: \.self) { column in
                    Circle()
                        .fill(Constants.OnSurface)
                        .frame(width: Metrics.dotSize, height: Metrics.dotSize)
                        .position(
                            x: Metrics.dotLeadingByColumn[column] + (Metrics.dotSize / 2),
                            y: Metrics.dotTop + CGFloat(row) * Metrics.rowStep + (Metrics.dotSize / 2)
                        )
                }
            }

            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                CachedRemoteImage(
                    url: URL(string: photo.url),
                    targetSize: Metrics.cardSize
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Constants.Black.opacity(0.2))
                }
                .frame(width: Metrics.cardSize.width, height: Metrics.cardSize.height)
                .background(Constants.Black)
                .clipShape(.rect(cornerRadius: Metrics.cardCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                        .stroke(Constants.ContentM, lineWidth: 1)
                }
                .position(photoPosition(for: index))
                .onAppear {
                    if index == photos.count - 1 && hasMore {
                        onLoadMore()
                    }
                }
            }

        }
        .frame(width: Metrics.boardWidth, height: boardHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Metrics.boardCornerRadius))
    }

    private func photoPosition(for index: Int) -> CGPoint {
        let row = index / Metrics.columnCount
        let column = index % Metrics.columnCount
        return CGPoint(
            x: Metrics.cardLeadingByColumn[column] + (Metrics.cardSize.width / 2),
            y: Metrics.cardTop + CGFloat(row) * Metrics.rowStep + (Metrics.cardSize.height / 2)
        )
    }
}

#Preview {
    TripPhotoSection(
        photos: [],
        isLoading: false,
        hasMore: false,
        isUploading: false,
        uploadProgress: 0,
        onLoadMore: {},
        onPhotoTapped: {},
        onPhotosSelected: { _ in }
    )
    .padding()
    .background(Constants.Background)
}
