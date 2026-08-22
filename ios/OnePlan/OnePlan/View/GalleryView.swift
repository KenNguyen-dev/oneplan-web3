//
//  GalleryView.swift
//  OnePlan
//
//  Created by ken on 7/4/26.
//

import SwiftUI

// MARK: - PhotoProtocol

protocol PhotoProtocol: HeroLightboxItem {}

extension TripPhotoDto: PhotoProtocol {}

// MARK: - PhotoGridView

struct PhotoGridView<Data: RandomAccessCollection, GridItem: View, Detail: View, Overlay: View>: View where Data.Element: PhotoProtocol {
    var spacing: CGFloat = 5
    var gridCount: Int = 3
    var gridItemHeight: CGFloat = 120
    var data: Data
    @ViewBuilder var gridItem: (Data.Element) -> GridItem
    @ViewBuilder var detail: (Data.Element, Bool, CGSize, @escaping () -> ()) -> Detail
    @ViewBuilder var overlay: (Data.Element?, Bool, CGSize, @escaping () -> ()) -> Overlay
    var onSelectionChanged: (Data.Element?) -> () = { _ in }
    /// View Properties
    @State private var config: HeroLightboxConfig<Data.Element> = .init()
    var body: some View {
        let gridItems = Array(repeating: SwiftUI.GridItem(spacing: spacing), count: gridCount)

        ScrollView(.vertical) {
            LazyVGrid(columns: gridItems, spacing: spacing) {
                ForEach(data, id: \.id) { item in
                    Rectangle()
                        .foregroundStyle(.clear)
                        .overlay {
                            GeometryReader {
                                let rect = $0.frame(in: .global)
                                let updatedRect: CGRect? = config.selectedItem == item ? rect : nil

                                gridItem(item)
                                    /// Hiding the source view when the hero effect is enabled
                                    .opacity(config.selectedItem == item ? 0 : 1)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(.rect)
                                    .onTapGesture {
                                        /// Storing info and opening full screen hero view
                                        config.selectedItem = item
                                        config.sourceLocation = rect
                                        /// Opening Full screen cover without animation
                                        withoutAnimation {
                                            config.showFullScreenCover = true
                                        }
                                    }
                                    /// Let's say when we change the selected on hero view by interacting with the page view, then we need to update the source location right?
                                    .onChange(of: updatedRect) { oldValue, newValue in
                                        if let newValue {
                                            config.sourceLocation = newValue
                                        }
                                    }
                            }
                        }
                        .frame(height: gridItemHeight)
                        .clipped()
                        .contentShape(.rect)
                }
            }
            .scrollTargetLayout()
        }
        .background(Constants.Background)
        .scrollPosition(id: $config.sourceScrollID)
        .fullScreenCover(isPresented: $config.showFullScreenCover) {
            config.selectedItem = nil
        } content: {
            HeroLightboxDetailView(config: $config, data: data, detail: detail, overlay: overlay)
        }
        /// Publishing selected item changes and also updating the source scroll view position when the item is changed from the hero detail view!
        .onChange(of: config.selectedItem) { oldValue, newValue in
            if let newValue, oldValue != nil {
                /// Not accounting the first initial change
                config.sourceScrollID = newValue.id
            }

            onSelectionChanged(newValue)
        }
    }
}

// MARK: - GalleryView

struct GalleryView: View {
    let tripName: String
    let photos: [TripPhotoDto]
    let hasMore: Bool
    let onLoadMore: () -> Void
    let onDelete: (TripPhotoDto) -> Void

    var body: some View {
        PhotoGridView(data: photos) { item in
            CachedRemoteImage(
                url: URL(string: item.url),
                targetSize: CGSize(width: 120, height: 120)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
            }
            .onAppear {
                if item.id == photos.last?.id, hasMore {
                    onLoadMore()
                }
            }
        } detail: { item, isExpanded, dragOffset, dismiss in
            VStack(spacing: 0) {
                if isExpanded {
                    Rectangle()
                        .foregroundStyle(.clear)
                        .frame(height: 80)
                }

                CachedRemoteImage(url: URL(string: item.url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isExpanded {
                    Rectangle()
                        .foregroundStyle(.clear)
                        .frame(height: 50)
                }
            }
        } overlay: { selectedItem, isExpanded, dragOffset, dismiss in
            GalleryOverlayView(
                selectedItem: selectedItem,
                dragOffset: dragOffset,
                dismiss: dismiss,
                onDelete: onDelete
            )
        } onSelectionChanged: { _ in

        }
        .safeAreaPadding(15)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(tripName)'s Photos")
                    .font(.headline)
            }
        }
    }
}

// MARK: - GalleryOverlayView

private struct GalleryOverlayView: View {
    let selectedItem: TripPhotoDto?
    let dragOffset: CGSize
    let dismiss: () -> Void
    let onDelete: (TripPhotoDto) -> Void

    @State private var isShowingDeleteAlert = false

    private var interactiveOpacity: CGFloat {
        1 - min(abs(dragOffset.height / 30), 1)
    }

    var body: some View {
        VStack {
            // MARK: Top Actions — avatar + "By ..." centered, trash on right
            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let avatarUrlString = selectedItem?.uploaderAvatarUrl,
                       let avatarUrl = URL(string: avatarUrlString) {
                        CachedRemoteImage(
                            url: avatarUrl,
                            targetSize: CGSize(width: 24, height: 24)
                        ) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .font(.callout)
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.callout)
                            .frame(width: 24, height: 24)
                    }

                    if let name = selectedItem?.uploaderDisplayName {
                        Text("By \(name)")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .clipShape(.capsule)
                .glassEffectCompat(in: Capsule(), interactive: false)

                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) {
                Button {
                    isShowingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                        .frame(width: 20, height: 30)
                }
                .glassButtonStyleCompat()
            }

            Spacer(minLength: 0)
        }
        .alert("Delete Photo", isPresented: $isShowingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = selectedItem {
                    onDelete(item)
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
        .padding(.horizontal, 15)
        .compositingGroup()
        .opacity(interactiveOpacity)
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    let samplePhotos: [TripPhotoDto] = [
        .init(id: 1, tripId: 1, url: "https://images.pexels.com/photos/18873058/pexels-photo-18873058.jpeg?w=800", uploadedById: 1, uploaderDisplayName: "Ken", uploaderAvatarUrl: "https://i.pravatar.cc/100?img=1", createdAt: "2026-04-01T10:00:00.000Z"),
        .init(id: 2, tripId: 1, url: "https://images.pexels.com/photos/20672997/pexels-photo-20672997.jpeg?w=800", uploadedById: 2, uploaderDisplayName: "Alice", uploaderAvatarUrl: "https://i.pravatar.cc/100?img=5", createdAt: "2026-04-01T11:00:00.000Z"),
        .init(id: 3, tripId: 1, url: "https://images.pexels.com/photos/1037995/pexels-photo-1037995.jpeg?w=800", uploadedById: 1, uploaderDisplayName: "Ken", uploaderAvatarUrl: "https://i.pravatar.cc/100?img=1", createdAt: "2026-04-01T12:00:00.000Z"),
        .init(id: 4, tripId: 1, url: "https://images.pexels.com/photos/2911519/pexels-photo-2911519.jpeg?w=800", uploadedById: 3, uploaderDisplayName: "Bob", createdAt: "2026-04-02T09:00:00.000Z"),
        .init(id: 5, tripId: 1, url: "https://images.pexels.com/photos/4040654/pexels-photo-4040654.jpeg?w=800", uploadedById: 2, uploaderDisplayName: "Alice", uploaderAvatarUrl: "https://i.pravatar.cc/100?img=5", createdAt: "2026-04-02T10:00:00.000Z"),
        .init(id: 6, tripId: 1, url: "https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?w=800", uploadedById: 1, uploaderDisplayName: "Ken", uploaderAvatarUrl: "https://i.pravatar.cc/100?img=1", createdAt: "2026-04-02T14:00:00.000Z"),
        .init(id: 7, tripId: 1, url: "https://images.pexels.com/photos/3225517/pexels-photo-3225517.jpeg?w=800", uploadedById: 3, uploaderDisplayName: "Bob", createdAt: "2026-04-03T08:00:00.000Z"),
        .init(id: 8, tripId: 1, url: "https://images.pexels.com/photos/2662116/pexels-photo-2662116.jpeg?w=800", uploadedById: 2, uploaderDisplayName: "Alice", uploaderAvatarUrl: "https://i.pravatar.cc/100?img=5", createdAt: "2026-04-03T16:00:00.000Z"),
    ]

    NavigationStack {
        GalleryView(
            tripName: "Da Lat",
            photos: samplePhotos,
            hasMore: false,
            onLoadMore: {},
            onDelete: { _ in }
        )
    }
}
