//
//  ChatList.swift
//  OnePlan
//
//  Created by Codex on 27/2/26.
//

import SwiftUI

struct ChatListEntry: Identifiable, Hashable {
    let tripId: Int
    var id: Int { tripId }
    let name: String
    let coverImageUrl: String?
    let latestMessageId: Int?
    let message: String
    let dateText: String
    let imageNames: [String]
    let hasStatusDot: Bool
    let extraMemberCount: Int?
}

private struct ChatListItem: View {
    let entry: ChatListEntry
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ChatAvatar(entry: entry)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(entry.name)
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundColor(Constants.ContentB)
                            .lineLimit(1)

                        if entry.hasStatusDot {
                            Circle()
                                .fill(Constants.BlueBase)
                                .frame(width: 8, height: 8)
                        }
                        
                        Spacer()
                        
                        Text(entry.dateText)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentM)
                            .lineLimit(1)
                    }

                    Text(entry.message)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(entry.hasStatusDot ? Constants.ContentB : Constants.ContentM)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if showsDivider {
                Divider()
                    .overlay(Constants.Neutral100)
                    .padding(.horizontal, 12)
            }
        }
    }
}

private struct ChatAvatar: View {
    let entry: ChatListEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = entry.coverImageUrl, let url = URL(string: urlString) {
                CachedRemoteImage(url: url, targetSize: CGSize(width: 48, height: 48)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("defaultTripPlaceholder")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            } else if entry.imageNames.count > 1 {
                HStack(spacing: -12) {
                    ForEach(Array(entry.imageNames.prefix(2).enumerated()), id: \.offset) { _, imageName in
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Constants.Surface, lineWidth: 2)
                            )
                    }
                }
                .frame(width: 44, alignment: .leading)
                .padding(.leading, 4)
            } else {
                Image(entry.imageNames.first ?? "defaultTripPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            }

            if let extraMemberCount = entry.extraMemberCount {
                Text("+\(extraMemberCount)")
                    .font(
                        Font.beVietnamPro(10, weight: .semibold)
                    )
                    .foregroundColor(Constants.White)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Constants.Green500)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Constants.Surface, lineWidth: 1)
                    )
                    .offset(x: -2, y: 3)
            }
        }
        .frame(width: 48, height: 48)
    }
}

private struct ChatListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatListSizingContent: View {
    let entries: [ChatListEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ChatListItem(entry: entry, showsDivider: index < entries.count - 1)
            }
        }
    }
}

struct ChatList: View {
    let entries: [ChatListEntry]
    var onTap: ((ChatListEntry) -> Void)?
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    onTap?(entry)
                } label: {
                    ChatListItem(entry: entry, showsDivider: index < entries.count - 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            ChatListSizingContent(entries: entries)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ChatListHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(ChatListHeightPreferenceKey.self) { height in
            contentHeight = max(height, 1)
        }
        .frame(height: contentHeight)
        .background(Constants.Surface)
        .cornerRadius(24)
    }
}

#Preview {
    ChatList(
        entries: [
            ChatListEntry(
                tripId: 1,
                name: "Huy",
                coverImageUrl: nil,
                latestMessageId: nil,
                message: "You: Hello, remember to setup an alarm for tomorrow guys.",
                dateText: "14/11/2025",
                imageNames: ["defaultTripPlaceholder"],
                hasStatusDot: false,
                extraMemberCount: nil
            ),
            ChatListEntry(
                tripId: 2,
                name: "Hyy",
                coverImageUrl: nil,
                latestMessageId: nil,
                message: "Hello, are you there",
                dateText: "14/11/2025",
                imageNames: ["defaultTripPlaceholder"],
                hasStatusDot: false,
                extraMemberCount: nil
            ),
            ChatListEntry(
                tripId: 3,
                name: "Carlos",
                coverImageUrl: nil,
                latestMessageId: nil,
                message: "gm champ, let’s celebrate a party",
                dateText: "14/11/2025",
                imageNames: ["defaultTripPlaceholder"],
                hasStatusDot: true,
                extraMemberCount: nil
            ),
            ChatListEntry(
                tripId: 4,
                name: "Dubai 2025",
                coverImageUrl: nil,
                latestMessageId: nil,
                message: "Huy: Breakfast time boys. Let’s destroy itttt!!!",
                dateText: "14/11/2025",
                imageNames: ["defaultTripPlaceholder", "defaultTripPlaceholder"],
                hasStatusDot: true,
                extraMemberCount: 3
            ),
        ]
    )
    .padding()
    .background(Constants.Background)
}
