//
//  ChatBubble.swift
//  OnePlan
//
//  Created by ken on 28/3/26.
//

import SwiftUI

struct ChatBubble: View {
    enum Style {
        case incoming
        case outgoing
        case notification

        var backgroundColor: Color {
            switch self {
            case .incoming: Constants.Surface
            case .outgoing: Constants.BlueBase
            case .notification: .clear
            }
        }

        var textColor: Color {
            switch self {
            case .incoming: Constants.ContentB
            case .outgoing: Constants.White
            case .notification: Constants.ContentM
            }
        }

        var topLeadingRadius: CGFloat {
            switch self {
            case .incoming: 4
            case .outgoing: 16
            case .notification: 0
            }
        }

        var topTrailingRadius: CGFloat {
            16
        }

        var bottomLeadingRadius: CGFloat {
            16
        }

        var bottomTrailingRadius: CGFloat {
            switch self {
            case .incoming: 16
            case .outgoing: 4
            case .notification: 0
            }
        }
    }

    let text: String
    var style: Style = .incoming
    var senderName: String? = nil
    var avatarUrl: String? = nil
    var imageUrl: String? = nil
    var isImageSelected: Bool = false
    var onImageTapped: ((CGRect) -> Void)? = nil
    var onSelectedImageFrameChanged: ((CGRect) -> Void)? = nil

    var body: some View {
        Group {
            if style == .incoming, showsSenderMetadata {
                HStack(alignment: .top, spacing: 8) {
                    avatarView

                    VStack(alignment: .leading, spacing: 4) {
                        if let senderName {
                            Text(senderName)
                                .font(Font.beVietnamPro(14, weight: .medium))
                                .foregroundStyle(Constants.ContentM)
                                .lineLimit(1)
                        }

                        bubbleBody
                    }
                }
            } else {
                bubbleBody
                    .padding(.leading, incomingLeftInsetWithoutMetadata)
            }
        }
    }

    private var showsSenderMetadata: Bool {
        senderName != nil || avatarUrl != nil
    }

    private var incomingLeftInsetWithoutMetadata: CGFloat {
        guard style == .incoming, !showsSenderMetadata else { return 0 }
        return 32 // 24 avatar + 8 spacing to align grouped incoming bubbles
    }

    private var avatarView: some View {
        Group {
            if let avatarUrl, let url = URL(string: avatarUrl) {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: 48, height: 48)
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("avatarPlaceholder")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Image("avatarPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if style == .notification {
            Text(text)
                .font(.beVietnamPro(13, weight: .medium))
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: hasImage && hasText ? 8 : 0) {
                if hasImage {
                    imageContent
                }

                if hasText {
                    Text(trimmedText)
                        .font(.custom("Be Vietnam Pro", size: 15))
                        .foregroundStyle(style.textColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .padding(textPadding)
                }
            }
                .background(style.backgroundColor)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: style.topLeadingRadius,
                        bottomLeadingRadius: style.bottomLeadingRadius,
                        bottomTrailingRadius: style.bottomTrailingRadius,
                        topTrailingRadius: style.topTrailingRadius
                    )
                )
                .frame(maxWidth: 220, alignment: style == .outgoing ? .trailing : .leading)
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasText: Bool {
        !trimmedText.isEmpty
    }

    private var resolvedImageURL: URL? {
        guard let imageUrl else { return nil }
        return URL(string: imageUrl)
    }

    private var hasImage: Bool {
        resolvedImageURL != nil
    }

    private var textPadding: EdgeInsets {
        if hasImage {
            return .init(top: 0, leading: 10, bottom: 10, trailing: 10)
        }
        return .init(top: 10, leading: 10, bottom: 10, trailing: 10)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let imageURL = resolvedImageURL {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .global)

                CachedRemoteImage(
                    url: imageURL,
                    targetSize: CGSize(width: 220, height: 220)
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Constants.Black.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                }
                .opacity(isImageSelected ? 0 : 1)
                .contentShape(.rect)
                .onTapGesture {
                    onImageTapped?(rect)
                }
                .onChange(of: isImageSelected ? rect : nil) { _, newValue in
                    if let newValue {
                        onSelectedImageFrameChanged?(newValue)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .clipped()
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ChatBubble(
            text: "No messages yet. Say Hello!",
            style: .notification
        )
        ChatBubble(
            text: "Hello, remember to setup an alarm for tomorrow go?",
            style: .incoming,
            senderName: "Ken",
            avatarUrl: nil
        )
        ChatBubble(
            text: "Hello, remember to setup an alarm for tomorrow go?",
            style: .outgoing
        )
        ChatBubble(
            text: "",
            style: .incoming,
            senderName: "Linh",
            avatarUrl: nil,
            imageUrl: "https://images.pexels.com/photos/2662116/pexels-photo-2662116.jpeg?w=800"
        )
    }
    .padding()
    .background(Constants.Background)
}
