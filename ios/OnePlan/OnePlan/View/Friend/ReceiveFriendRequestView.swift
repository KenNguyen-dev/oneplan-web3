//
//  FriendRequestView.swift
//  OnePlan
//
//  Created by ken on 9/3/26.
//

import SwiftUI
import UIKit

struct ReceiveFriendRequestView: View {
    let requestId: Int
    let senderName: String
    let senderAvatarUrl: String?
    let mutualFriendCount: Int
    var onAccept: () -> Void = {}
    var onDismiss: () -> Void = {}
    @State private var friendService = FriendService()
    @State private var isDismissing = false

    var body: some View {
        ZStack(alignment: .top) {
            Image("inviteBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            friendRequestBody
                .padding(.top,160)
        }
        .overlay(alignment: .bottom) {
            FriendRequestDismissButton(action: onDismiss)
                .disabled(isDismissing)
                .padding(.bottom, 80)
        }
        
    }

    private var friendRequestBody: some View {
        VStack(spacing: 50) {
            VStack(spacing: 6) {
                Text("Friend request from\n\u{201C}\(senderName)\u{201D}")
                  .font(Font.custom("Be Vietnam Pro", size: 24))
                  .multilineTextAlignment(.center)
                  .foregroundColor(Constants.ContentB)
                  .frame(maxWidth: .infinity, alignment: .top)

                HStack(spacing: 3) {
                    FriendRequestMutualAvatarStrip()
                    Text("\(mutualFriendCount) mutual friends")
                      .font(Font.custom("Be Vietnam Pro", size: 14))
                      .foregroundColor(Constants.ContentM)
                }
            }

            FriendRequestAvatarBadge(
                ringPhrase: avatarRingPhrase,
                avatarUrl: senderAvatarUrl
            )

            AddFriendButton(title: "Accept") {
                SheetOpeningSoundPlayer.shared.playNavigateFromSheet()
                onAccept()
            }
                .frame(width: 150)
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarRingPhrase: String {
        let normalizedName = senderName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let displayName = normalizedName.isEmpty ? "MEMBER" : normalizedName
        return "\(displayName) - MEMBER SINCE 2025"
    }

    private func dismissAndReject() {
        guard !isDismissing else { return }
        isDismissing = true

        Task {
            defer { isDismissing = false }
            try? await friendService.respondToRequest(
                id: requestId,
                accept: false
            )
            onDismiss()
        }
    }
}

private struct FriendRequestAvatarBadge: View {
    let ringPhrase: String
    let avatarUrl: String?
    private let badgeSize: CGFloat = 213.479
    private let photoSize: CGFloat = 174
    private let textRadius: CGFloat = 95
    @State private var ringRotationDegrees: Double = 0

    private var ringText: String {
        "\(ringPhrase) - \(ringPhrase) -"
    }

    var body: some View {
        ZStack {
            AngularGradient(
                gradient: Gradient(
                    stops: [
                        .init(
                            color: Color(red: 0.42, green: 0.49, blue: 1.0),
                            location: 0.03
                        ),
                        .init(
                            color: Color(red: 0.5, green: 0.34, blue: 0.93),
                            location: 0.29
                        ),
                        .init(
                            color: Color(red: 0.94, green: 0.37, blue: 0.66),
                            location: 0.55
                        ),
                        .init(
                            color: Color(red: 1.0, green: 0.59, blue: 0.08),
                            location: 0.8
                        ),
                        .init(
                            color: Color(red: 0.42, green: 0.49, blue: 1.0),
                            location: 1
                        ),
                    ]
                ),
                center: .center,
                startAngle: .degrees(-65),
                endAngle: .degrees(295)
            )
            .frame(width: badgeSize, height: badgeSize)
            .mask(
                FriendRequestCircularTextGlyphs(
                    text: ringText,
                    size: badgeSize,
                    radius: textRadius
                )
            )
            .rotationEffect(.degrees(ringRotationDegrees))

            avatarImage
        }
        .frame(width: badgeSize, height: badgeSize)
        .onAppear {
            guard ringRotationDegrees == 0 else { return }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                ringRotationDegrees = 360
            }
        }
    }

    private var avatarImage: some View {
        let url = avatarUrl.flatMap(URL.init(string:))

        return CachedRemoteImage(
            url: url,
            targetSize: CGSize(width: photoSize, height: photoSize)
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image("avatarPlaceholder")
                .resizable()
                .scaledToFill()
        }
        .frame(width: photoSize, height: photoSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    Color(red: 0.835, green: 0.886, blue: 1),
                    lineWidth: 4
                )
        )
        .shadow(
            color: Color(red: 0.153, green: 0.294, blue: 1).opacity(
                0.83
            ),
            radius: 38.7,
            x: 0,
            y: 0
        )
    }
}

private struct FriendRequestCircularTextGlyphs: View {
    let text: String
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        FriendRequestCircularTextRenderer(text: text, radius: radius)
        .frame(width: size, height: size)
    }
}

private struct FriendRequestCircularTextRenderer: UIViewRepresentable {
    let text: String
    let radius: CGFloat

    func makeUIView(context: Context) -> FriendRequestCircularTextDrawingView {
        let view = FriendRequestCircularTextDrawingView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(
        _ uiView: FriendRequestCircularTextDrawingView,
        context: Context
    ) {
        uiView.configuration = .init(text: text, radius: radius)
    }
}

private final class FriendRequestCircularTextDrawingView: UIView {
    struct Configuration: Equatable {
        let text: String
        let radius: CGFloat
        let fontName: String = "BeVietnamPro-ExtraBold"
        let baseFontSize: CGFloat = 18
        let characterTracking: CGFloat = 0.55
        let targetFill: CGFloat = 0.972

        func fittedFontSize() -> CGFloat {
            let characters = Array(text)
            let font = uiFont(size: baseFontSize)
            let baseTotalWidth = characters.reduce(CGFloat.zero) { partial, character in
                partial
                    + characterWidth(String(character), font: font)
                    + characterTracking
            }
            guard baseTotalWidth > 0 else { return baseFontSize }

            let targetArcLength = 2 * .pi * radius * targetFill
            let scale = targetArcLength / baseTotalWidth
            return max(16, min(20, baseFontSize * scale))
        }

        func uiFont(size: CGFloat) -> UIFont {
            let candidateNames = [
                fontName,
                "BeVietnamPro-Black",
                "BeVietnamPro-Bold",
                "Be Vietnam Pro ExtraBold",
                "Be Vietnam Pro Black",
                "Be Vietnam Pro Bold",
                "Be Vietnam Pro",
            ]

            for name in candidateNames {
                if let font = UIFont(name: name, size: size) {
                    return font
                }
            }

            return UIFont.systemFont(ofSize: size, weight: .bold)
        }

        func characterWidth(_ value: String, font: UIFont) -> CGFloat {
            value.size(withAttributes: [.font: font]).width
        }

        func characterAdvance(_ value: String, font: UIFont) -> CGFloat {
            characterWidth(value, font: font) + characterTracking
        }
    }

    var configuration: Configuration = .init(text: "", radius: 0) {
        didSet {
            guard configuration != oldValue else { return }
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard
            let context = UIGraphicsGetCurrentContext(),
            configuration.radius > 0,
            !configuration.text.isEmpty
        else { return }

        let fontSize = configuration.fittedFontSize()
        let font = configuration.uiFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]

        let characters = Array(configuration.text)
        let advances = characters.map {
            configuration.characterAdvance(String($0), font: font)
        }
        let totalArcLength = advances.reduce(0, +)
        let startAngle = -CGFloat.pi / 2 - (totalArcLength / (2 * configuration.radius))
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var consumedArcLength: CGFloat = 0

        for (index, character) in characters.enumerated() {
            let value = String(character)
            let advance = advances[index]
            let centerArcLength = consumedArcLength + (advance / 2)
            let angle = startAngle + (centerArcLength / configuration.radius)
            let point = CGPoint(
                x: center.x + (configuration.radius * cos(angle)),
                y: center.y + (configuration.radius * sin(angle))
            )
            let glyphWidth = configuration.characterWidth(value, font: font)

            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.rotate(by: angle + (.pi / 2))

            (value as NSString).draw(
                at: CGPoint(x: -glyphWidth / 2, y: -font.ascender),
                withAttributes: attributes
            )

            context.restoreGState()
            consumedArcLength += advance
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentScaleFactor = UIScreen.main.scale
    }
}

private struct FriendRequestMutualAvatarStrip: View {
    var body: some View {
        HStack(spacing: -9) {
            friendAvatar
            friendAvatar
            friendAvatar
        }
    }

    private var friendAvatar: some View {
        Image("avatarPlaceholder")
            .resizable()
            .scaledToFill()
            .frame(width: 17, height: 17)
            .clipShape(Circle())
    }
}

private struct FriendRequestDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: Color(
                                        red: 0.925,
                                        green: 0.925,
                                        blue: 0.925
                                    ),
                                    location: 0
                                ),
                                .init(
                                    color: Color(
                                        red: 0.7,
                                        green: 0.7,
                                        blue: 0.7
                                    ),
                                    location: 0.745
                                ),
                                .init(
                                    color: Color(
                                        red: 0.922,
                                        green: 0.922,
                                        blue: 0.922
                                    ),
                                    location: 1
                                ),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .fill(Constants.White.opacity(0.85))
                    .frame(width: 43.658, height: 16.346)
                    .blur(radius: 2.3)
                    .offset(y: -18)
                    .blendMode(.plusLighter)

                Image(systemName: "xmark")
                    .font(.system(size: 17.8, weight: .light))
                    .foregroundStyle(Constants.ContentB.opacity(0.85))
            }
            .frame(width: 52, height: 52)
            .overlay {
                Circle()
                    .stroke(Constants.White, lineWidth: 1.5)
            }
            .shadow(
                color: Color(red: 0.588, green: 0.588, blue: 0.588).opacity(
                    0.25
                ),
                radius: 5.7,
                x: 0,
                y: 13
            )
            .shadow(
                color: Color(red: 0.765, green: 0.765, blue: 0.765).opacity(
                    0.39
                ),
                radius: 3.05,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ReceiveFriendRequestView(
        requestId: 1,
        senderName: "Cattie Oi",
        senderAvatarUrl: nil,
        mutualFriendCount: 25
    )
}
