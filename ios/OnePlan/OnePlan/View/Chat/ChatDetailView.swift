//
//  ChatDetailView.swift
//  OnePlan
//
//  Created by ken on 28/3/26.
//

import SwiftUI
import PhotosUI
import UIKit

struct ChatDetailView: View {
    private static let bottomAnchorId = "chat-bottom-anchor"

    struct PreviewMessage: Identifiable {
        let id: Int
        let content: String
        let imageUrl: String?
        let isOutgoing: Bool
        let senderName: String?
        let avatarUrl: String?

        init(
            id: Int,
            content: String,
            imageUrl: String? = nil,
            isOutgoing: Bool,
            senderName: String?,
            avatarUrl: String?
        ) {
            self.id = id
            self.content = content
            self.imageUrl = imageUrl
            self.isOutgoing = isOutgoing
            self.senderName = senderName
            self.avatarUrl = avatarUrl
        }
    }

    private struct MessageRow: Identifiable {
        let id: Int
        let content: String
        let imageUrl: String?
        let isOutgoing: Bool
        let senderName: String?
        let avatarUrl: String?
        let senderKey: String?
    }

    private struct ChatImageLightboxItem: HeroLightboxItem {
        let id: Int
        let urlString: String
    }

    let tripId: Int
    let tripName: String
    let coverImageUrl: String?
    var previewMessages: [PreviewMessage] = []

    @Environment(UserProfileService.self) private var userProfileService
    @Environment(RealtimeService.self) private var realtimeService
    @State private var storageUploadService = StorageUploadService()
    @State private var messageText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingTripDetail = false
    @State private var paginationAnchorMessageId: Int?
    @State private var imageLightboxConfig: HeroLightboxConfig<ChatImageLightboxItem> = .init()
    @FocusState private var isActive: Bool

    private var currentUserId: Int? {
        userProfileService.profile?.id
    }

    private var rows: [MessageRow] {
        let baseRows: [MessageRow]
        if !previewMessages.isEmpty {
            baseRows = previewMessages.map { preview in
                MessageRow(
                    id: preview.id,
                    content: preview.content,
                    imageUrl: preview.imageUrl,
                    isOutgoing: preview.isOutgoing,
                    senderName: preview.senderName,
                    avatarUrl: preview.avatarUrl,
                    senderKey: preview.isOutgoing ? nil : preview.senderName
                )
            }
            return rowsWithCondensedSenderNames(from: baseRows)
        }

        baseRows = realtimeService.messages.map { message in
            let isOutgoing = message.senderId == currentUserId
            return MessageRow(
                id: message.id,
                content: message.content,
                imageUrl: message.imageUrl,
                isOutgoing: isOutgoing,
                senderName: message.senderDisplayName,
                avatarUrl: message.senderAvatarUrl,
                senderKey: isOutgoing ? nil : message.senderId.map { String($0) } ?? "deleted"
            )
        }
        return rowsWithCondensedSenderNames(from: baseRows)
    }

    private var latestIncomingMessageId: Int? {
        guard let currentUserId else { return nil }
        return realtimeService.messages.last(where: { $0.senderId != currentUserId })?.id
    }

    private var chatImageItems: [ChatImageLightboxItem] {
        rows.compactMap { row in
            guard let imageUrl = row.imageUrl, URL(string: imageUrl) != nil else {
                return nil
            }
            return ChatImageLightboxItem(id: row.id, urlString: imageUrl)
        }
    }

    private func rowsWithCondensedSenderNames(from sourceRows: [MessageRow]) -> [MessageRow] {
        var result: [MessageRow] = []
        result.reserveCapacity(sourceRows.count)

        var previousIncomingSenderKey: String?
        var incomingStreakCount = 0

        for row in sourceRows {
            guard !row.isOutgoing, let senderKey = row.senderKey else {
                previousIncomingSenderKey = nil
                incomingStreakCount = 0
                result.append(row)
                continue
            }

            if senderKey == previousIncomingSenderKey {
                incomingStreakCount += 1
            } else {
                previousIncomingSenderKey = senderKey
                incomingStreakCount = 1
            }

            let senderNameToShow = incomingStreakCount > 1 ? nil : row.senderName
            result.append(
                MessageRow(
                    id: row.id,
                    content: row.content,
                    imageUrl: row.imageUrl,
                    isOutgoing: row.isOutgoing,
                    senderName: senderNameToShow,
                    avatarUrl: row.avatarUrl,
                    senderKey: row.senderKey
                )
            )
        }

        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if realtimeService.isLoadingHistory {
                        ProgressView()
                            .padding(.top, 40)
                    } else if rows.isEmpty {
                        ChatBubble(
                            text: "No messages yet. Say Hello!",
                            style: .notification
                        )
                        .padding(.top, 40)
                    }

                    if realtimeService.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                    }

                    ForEach(rows) { row in
                        ChatBubble(
                            text: row.content,
                            style: row.isOutgoing ? .outgoing : .incoming,
                            senderName: row.isOutgoing ? nil : row.senderName,
                            avatarUrl: row.isOutgoing ? nil : row.avatarUrl,
                            imageUrl: row.imageUrl,
                            isImageSelected: imageLightboxConfig.selectedItem?.id == row.id,
                            onImageTapped: { rect in
                                guard let item = chatImageItem(for: row) else { return }
                                imageLightboxConfig.selectedItem = item
                                imageLightboxConfig.sourceLocation = rect
                                withoutAnimation {
                                    imageLightboxConfig.showFullScreenCover = true
                                }
                            },
                            onSelectedImageFrameChanged: { rect in
                                imageLightboxConfig.sourceLocation = rect
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: row.isOutgoing ? .trailing : .leading)
                        .id(row.id)
                        .onAppear {
                            loadOlderMessagesIfNeeded(currentTopRowId: row.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorId)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        guard isActive else { return }
                        isActive = false
                    }
            )
            .frame(maxWidth: .infinity)
            .background(Constants.Background)
            .onChange(of: rows.first?.id) { previousTopRowId, currentTopRowId in
                guard
                    let anchorMessageId = paginationAnchorMessageId,
                    previousTopRowId != currentTopRowId
                else {
                    return
                }

                DispatchQueue.main.async {
                    proxy.scrollTo(anchorMessageId, anchor: .top)
                    paginationAnchorMessageId = nil
                }
            }
            .onChange(of: rows.last?.id) { previousBottomRowId, currentBottomRowId in
                guard
                    previousBottomRowId != currentBottomRowId,
                    currentBottomRowId != nil,
                    paginationAnchorMessageId == nil
                else {
                    return
                }

                withAnimation {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: isActive) { _, isFocused in
                guard isFocused else { return }
                DispatchQueue.main.async {
                    withAnimation {
                        proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: imageLightboxConfig.selectedItem) { oldValue, newValue in
                guard let newValue, oldValue != nil else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(newValue.id, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .fullScreenCover(isPresented: $imageLightboxConfig.showFullScreenCover) {
            imageLightboxConfig.selectedItem = nil
        } content: {
            HeroLightboxDetailView(
                config: $imageLightboxConfig,
                data: chatImageItems
            ) { item, isExpanded, _, _ in
                CachedRemoteImage(url: URL(string: item.urlString)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } overlay: { _, _, _, _ in
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    isShowingTripDetail = true
                } label: {
                    VStack(spacing: 4) {
                        Group {
                            if let urlString = coverImageUrl,
                                let url = URL(string: urlString)
                            {
                                CachedRemoteImage(
                                    url: url,
                                    targetSize: CGSize(width: 56, height: 56)
                                ) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image("defaultTripPlaceholder")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            } else {
                                Image("defaultTripPlaceholder")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())

                        Text(tripName)
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundStyle(Constants.ContentB)
                    }
                    .padding(.top, 24)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(isPresented: $isShowingTripDetail) {
            TripDetailView(tripId: tripId)
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await sendPhotoMessage(item: newItem)
            }
        }
        .onChange(of: latestIncomingMessageId) { _, newValue in
            guard previewMessages.isEmpty, let messageId = newValue else { return }
            Task {
                await realtimeService.markTripSeen(tripId: tripId, messageId: messageId)
            }
        }
        .task {
            guard previewMessages.isEmpty else { return }
            await realtimeService.joinTrip(tripId: tripId)
        }
        .onAppear {
            guard previewMessages.isEmpty else { return }
            ActiveChatTracker.shared.activeTripId = tripId
            isActive = true
        }
        .onDisappear {
            guard previewMessages.isEmpty else { return }
            ActiveChatTracker.shared.activeTripId = nil
            realtimeService.leaveTrip(tripId: tripId)
        }
    }

    @ViewBuilder
    func BottomBar() -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Constants.DividerStroke)
                .frame(height: 1)

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Group {
                        if storageUploadService.isUploading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Constants.BlueBase)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Constants.ContentB)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                .disabled(storageUploadService.isUploading || !isInteractive)

                TextField("Message", text: $messageText)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 15)
                    .background {
                        Capsule()
                            .stroke(Constants.Neutral200, lineWidth: 1.5)
                    }
                    .focused($isActive)
                    .onSubmit {
                        sendCurrentMessage()
                    }

                Button {
                    sendCurrentMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            canSend ? Constants.BlueBase : Constants.Neutral200
                        )
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Constants.White)
    }

    private var canSend: Bool {
        isInteractive && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isInteractive: Bool {
        previewMessages.isEmpty
    }

    private func loadOlderMessagesIfNeeded(currentTopRowId: Int) {
        guard
            isInteractive,
            realtimeService.hasMoreHistory,
            !realtimeService.isLoadingHistory,
            !realtimeService.isLoadingMore,
            rows.first?.id == currentTopRowId
        else {
            return
        }

        paginationAnchorMessageId = currentTopRowId
        Task {
            await realtimeService.loadMoreHistory()
        }
    }

    private func chatImageItem(for row: MessageRow) -> ChatImageLightboxItem? {
        guard let imageUrl = row.imageUrl, URL(string: imageUrl) != nil else {
            return nil
        }
        return ChatImageLightboxItem(id: row.id, urlString: imageUrl)
    }

    private func sendCurrentMessage() {
        guard canSend else { return }
        realtimeService.sendMessage(content: messageText)
        messageText = ""
    }

    private func sendPhotoMessage(item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        guard isInteractive, !storageUploadService.isUploading else { return }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                return
            }

            let result = try await storageUploadService.uploadImage(
                image,
                target: .trip_hyphen_photo,
                entityId: tripId
            )

            realtimeService.sendImageMessage(objectKey: result.objectKey)
            NotificationCenter.default.post(
                name: .tripPhotoUploaded,
                object: nil,
                userInfo: ["tripId": tripId]
            )
        } catch {
            realtimeService.error = storageUploadService.error ?? "Failed to upload image"
        }
    }
}

#Preview {
    NavigationStack {
        ChatDetailView(
            tripId: 1,
            tripName: "Dubai 2025",
            coverImageUrl: nil,
            previewMessages: [
                .init(id: 1, content: "Hi everyone!", isOutgoing: false, senderName: "Ken", avatarUrl: nil),
                .init(id: 2, content: "Landing around 6 PM.", isOutgoing: false, senderName: "Linh", avatarUrl: nil),
                .init(id: 3, content: "", imageUrl: "https://images.pexels.com/photos/2662116/pexels-photo-2662116.jpeg?w=900", isOutgoing: false, senderName: "Linh", avatarUrl: nil),
                .init(id: 4, content: "Great, I'll book the ride.", isOutgoing: true, senderName: nil, avatarUrl: nil),
                .init(id: 5, content: "", imageUrl: "https://images.pexels.com/photos/3225517/pexels-photo-3225517.jpeg?w=900", isOutgoing: true, senderName: nil, avatarUrl: nil),
                .init(id: 6, content: "Perfect. See you soon.", isOutgoing: false, senderName: "Ken", avatarUrl: nil),
            ]
        )
            .environment(UserProfileService())
            .environment(RealtimeService())
    }
}
