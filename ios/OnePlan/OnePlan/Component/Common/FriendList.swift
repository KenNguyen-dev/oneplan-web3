//
//  FriendList.swift
//  OnePlan
//
//  Created by Codex on 3/4/26.
//

import SwiftUI

struct FriendListEntry: Identifiable {
    enum TrailingAction {
        case invite
        case sent

        var text: String {
            switch self {
            case .invite:
                return String(localized: "Invite", comment: "Friend list action")
            case .sent:
                return String(localized: "Sent", comment: "Friend request already sent")
            }
        }

        var isEnabled: Bool {
            switch self {
            case .invite:
                return true
            case .sent:
                return false
            }
        }
    }

    let id: String
    let name: String
    let subtitleText: String
    let imageName: String
    let avatarUrl: String?
    let trailingAction: TrailingAction?
    let isPro: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        subtitleText: String,
        imageName: String = "avatarPlaceholder",
        avatarUrl: String? = nil,
        trailingAction: TrailingAction? = nil,
        isPro: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitleText = subtitleText
        self.imageName = imageName
        self.avatarUrl = avatarUrl
        self.trailingAction = trailingAction
        self.isPro = isPro
    }

    init(from member: TripMemberDto) {
        self.id = "\(member.id)"
        self.name = member.displayName
        self.subtitleText = member.inviteStatus.value1.rawValue.capitalized
        self.imageName = "avatarPlaceholder"
        self.avatarUrl = member.avatarUrl
        self.trailingAction = nil
        self.isPro = false
    }
}

private struct FriendListItem: View {
    let entry: FriendListEntry
    let onItemTapped: ((FriendListEntry) -> Void)?
    let onTrailingActionTapped: ((FriendListEntry) -> Void)?
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let imageSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var body: some View {
        if let onItemTapped {
            Button {
                onItemTapped(entry)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if entry.isPro {
                AvatarProPlaceholder(
                    size: imageSize,
                    imageUrl: entry.avatarUrl,
                    placeholderImageName: entry.imageName,
                    showBadge: true
                )
            } else {
                plainAvatar
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(
                        Font.beVietnamPro(titleFontSize, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)

                Text(entry.subtitleText)
                    .font(Font.custom("Be Vietnam Pro", size: subtitleFontSize))
                    .foregroundColor(Constants.ContentM)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let trailingAction = entry.trailingAction {
                Button {
                    guard trailingAction.isEnabled else { return }
                    onTrailingActionTapped?(entry)
                } label: {
                    Text(trailingAction.text)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(
                            trailingAction.isEnabled
                                ? Constants.White
                                : Constants.ContentL
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            trailingAction.isEnabled
                                ? Constants.Black
                                : Constants.Neutral200
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!trailingAction.isEnabled)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    @ViewBuilder
    private var plainAvatar: some View {
        if let urlString = entry.avatarUrl, let url = URL(string: urlString) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: imageSize, height: imageSize)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(entry.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: imageSize, height: imageSize)
            .clipShape(Circle())
        } else {
            Image(entry.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: imageSize, height: imageSize)
                .clipShape(Circle())
        }
    }
}

private struct FriendListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FriendListSizingContent: View {
    let entries: [FriendListEntry]
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let imageSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                FriendListItem(
                    entry: entry,
                    onItemTapped: nil,
                    onTrailingActionTapped: nil,
                    titleFontSize: titleFontSize,
                    subtitleFontSize: subtitleFontSize,
                    imageSize: imageSize,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding
                )
            }
        }
    }
}

struct FriendList: View {
    let entries: [FriendListEntry]
    let onItemTapped: ((FriendListEntry) -> Void)?
    let onTrailingActionTapped: ((FriendListEntry) -> Void)?
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let imageSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @State private var contentHeight: CGFloat = 1

    init(
        entries: [FriendListEntry] = FriendList.defaultEntries,
        onItemTapped: ((FriendListEntry) -> Void)? = nil,
        onTrailingActionTapped: ((FriendListEntry) -> Void)? = nil,
        titleFontSize: CGFloat = 14,
        subtitleFontSize: CGFloat = 12,
        imageSize: CGFloat = 48,
        horizontalPadding: CGFloat = 14,
        verticalPadding: CGFloat = 10
    ) {
        self.entries = entries
        self.onItemTapped = onItemTapped
        self.onTrailingActionTapped = onTrailingActionTapped
        self.titleFontSize = titleFontSize
        self.subtitleFontSize = subtitleFontSize
        self.imageSize = imageSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    @_disfavoredOverload
    @available(*, deprecated, message: "Use imageSize, horizontalPadding, and verticalPadding")
    init(
        entries: [FriendListEntry] = FriendList.defaultEntries,
        onTrailingActionTapped: ((FriendListEntry) -> Void)? = nil,
        titleFontSize: CGFloat = 20,
        subtitleFontSize: CGFloat = 14,
        imageWidth: CGFloat = 56,
        imageHeight: CGFloat = 56,
        usesPadding: Bool = true
    ) {
        self.init(
            entries: entries,
            onItemTapped: nil,
            onTrailingActionTapped: onTrailingActionTapped,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            imageSize: imageWidth == imageHeight ? imageWidth : min(imageWidth, imageHeight),
            horizontalPadding: usesPadding ? 14 : 0,
            verticalPadding: usesPadding ? 10 : 0
        )
    }

    var body: some View {
        List(entries) { entry in
            FriendListItem(
                entry: entry,
                onItemTapped: onItemTapped,
                onTrailingActionTapped: onTrailingActionTapped,
                titleFontSize: titleFontSize,
                subtitleFontSize: subtitleFontSize,
                imageSize: imageSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            FriendListSizingContent(
                entries: entries,
                titleFontSize: titleFontSize,
                subtitleFontSize: subtitleFontSize,
                imageSize: imageSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FriendListHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(FriendListHeightPreferenceKey.self) { height in
            contentHeight = max(height, 1)
        }
        .frame(height: contentHeight)
        .background(Constants.Surface)
        .cornerRadius(24)
    }
}

private extension FriendList {
    static let defaultEntries: [FriendListEntry] = [
        FriendListEntry(name: "Cattie", subtitleText: "12 mutual friends", imageName: "avatarPlaceholder"),
        FriendListEntry(name: "hmy", subtitleText: "4 mutual friends", imageName: "avatarPlaceholder"),
        FriendListEntry(name: "Thanh Danh", subtitleText: "2 mutual friends", imageName: "avatarPlaceholder"),
        FriendListEntry(name: "Shin", subtitleText: "2 mutual friends", imageName: "avatarPlaceholder"),
    ]
}

#Preview {
    FriendList()
        .padding()
        .background(Constants.Background)
}
