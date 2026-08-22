//
//  SendFriendRequestView.swift
//  OnePlan
//
//  Created by ken on 2/4/26.
//

import SwiftUI
import UIKit

struct SendFriendRequestView: View {
    let friendCode: String
    var onDismiss: () -> Void = {}

    @State private var preview: FriendPreviewDto?
    @State private var isLoading = true
    @State private var isSending = false
    @State private var isCancelling = false
    @State private var didSendThisSession = false
    @State private var didCancelThisSession = false
    @State private var errorMessage: String?

    private let friendService = FriendService()

    var body: some View {
        VStack {
            sendFriendRequestBody
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Background)
        .overlay(alignment: .bottom) {
            DismissButton(action: onDismiss)
                .padding(.bottom, 33)
        }
        .task {
            await loadPreview()
        }
    }

    private var sendFriendRequestBody: some View {
        VStack(spacing: 0) {
            SendFriendRequestAvatarBadge(
                ringPhrase: preview.map {
                    "\($0.displayName.uppercased()) - MEMBER SINCE \($0.memberSince.prefix(4))"
                }
                    ?? "BELLA OI - MEMBER SINCE 2025",
                avatarUrl: preview?.avatarUrl
            )

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(preview?.displayName ?? "...")
                        .font(Font.custom("Be Vietnam Pro", size: 20))
                        .kerning(-1)
                        .foregroundStyle(Constants.ContentB)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 1))
                        .frame(width: 18, height: 18)
                }

                if let preview {
                    Text(memberSinceText(preview.memberSince))
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .kerning(-0.6)
                        .foregroundStyle(Constants.ContentM)
                }
            }
            .padding(.top, 19)

            VStack {
                if let status = preview?.requestStatus {
                    switch status {
                    case .friends:
                        Text("Already friends")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.ContentM)
                    case .pending_sent:
                        if didSendThisSession {
                            Text("Request sent")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundStyle(Constants.ContentM)
                        } else {
                            SecondaryButton(
                                title: "Cancel Request",
                                variant: .light,
                                action: cancelRequest
                            )
                            .opacity(isCancelling ? 0.5 : 1)
                            .allowsHitTesting(!isCancelling)
                        }
                    case .pending_received:
                        Text("Pending your response")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.ContentM)
                    case .none:
                        if didCancelThisSession {
                            Text("Request canceled")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundStyle(Constants.ContentM)
                        } else {
                            AddFriendButton(
                                title: "Add Friend",
                                action: sendRequest
                            )
                                .opacity(isSending ? 0.5 : 1)
                                .allowsHitTesting(!isSending)
                        }
                    }
                }
            }
            .frame(width: 150)
            .padding(.top, 19)

            if let preview {
                SendFriendRequestPassportSummarySection(
                    tripCount: preview.tripCount,
                    countryCount: preview.countryCount,
                    cityCount: preview.cityCount,
                    displayName: preview.displayName,
                    memberSince: preview.memberSince
                )
                .padding(.top, 38)
            }
        }
        .frame(maxWidth: .infinity)
        .redacted(reason: isLoading ? .placeholder : [])
    }

    private func loadPreview() async {
        do {
            preview = try await friendService.previewFriend(code: friendCode)
            didSendThisSession = false
            didCancelThisSession = false
        } catch {
            errorMessage = String(localized: "Failed to load profile")
        }
        isLoading = false
    }

    private func sendRequest() {
        Task {
            isSending = true
            defer { isSending = false }
            do {
                try await friendService.sendRequest(friendCode: friendCode)
                preview?.requestStatus = .pending_sent
                didSendThisSession = true
                didCancelThisSession = false
            } catch {
                errorMessage = String(localized: "Failed to send request")
            }
        }
    }

    private func cancelRequest() {
        Task {
            isCancelling = true
            defer { isCancelling = false }
            do {
                try await friendService.cancelSentRequest(friendCode: friendCode)
                preview?.requestStatus = .none
                didSendThisSession = false
                didCancelThisSession = true
            } catch {
                errorMessage = String(localized: "Failed to cancel request")
            }
        }
    }

    private func memberSinceText(_ isoDate: String) -> String {
        if let date = Self.memberSinceDate(from: isoDate) {
            return String(localized: "Member since \(DisplayFormatters.monthYear(date))", comment: "%@ = month and year")
        }

        if let year = isoDate.prefix(4).wholeMatch(of: /\d{4}/)?.output {
            return String(localized: "Member since \(String(year))", comment: "%@ = year")
        }

        return String(localized: "Member since")
    }

    private static func memberSinceDate(from value: String) -> Date? {
        isoFormatterWithFractionalSeconds.date(from: value)
            ?? isoFormatter.date(from: value)
            ?? isoDateOnlyFormatter.date(from: value)
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter =
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime, .withFractionalSeconds,
            ]
            return formatter
        }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let memberSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 435, height: 455)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }
}

private struct SendFriendRequestPassportSummarySection: View {
    let tripCount: Int
    let countryCount: Int
    let cityCount: Int
    let displayName: String
    let memberSince: String

    private let mrzColor = Color(red: 0.68, green: 0.68, blue: 0.68)

    private let flagKinds: [SendFriendRequestFlagKind] = [
        .vietnam, .philippines, .peru, .argentina, .brazil, .nigeria,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SendFriendRequestPassportMetricCard(
                    title: String(localized: "Trips"),
                    value: String(format: "%02d", tripCount)
                )
                SendFriendRequestPassportMetricCard(
                    title: String(localized: "Countries"),
                    value: String(format: "%02d", countryCount)
                )
                SendFriendRequestPassportMetricCard(
                    title: String(localized: "Cities"),
                    value: String(format: "%02d", cityCount)
                )
            }

            Divider()
                .overlay(Constants.Neutral100)
                .padding(.top, 30)

            HStack(spacing: -6.136) {
                ForEach(Array(flagKinds.enumerated()), id: \.offset) {
                    _,
                    kind in
                    SendFriendRequestPassportFlagBadge(kind: kind)
                }
            }
            .padding(.trailing, 6.136)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 34)

            PassportMRZLines(
                displayName: displayName,
                memberSince: memberSince,
                foregroundColor: mrzColor
            )
            .padding(.top, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SendFriendRequestPassportMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.6)
                .foregroundStyle(Constants.ContentM)

            Text(value)
                .font(Font.custom("Be Vietnam Pro", size: 20))
                .tracking(-1)
                .foregroundStyle(Constants.ContentB)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum SendFriendRequestFlagKind {
    case vietnam
    case philippines
    case peru
    case argentina
    case brazil
    case nigeria
}

private struct SendFriendRequestPassportFlagBadge: View {
    let kind: SendFriendRequestFlagKind

    var body: some View {
        ZStack {
            flagContent
                .frame(width: 24, height: 24)
                .clipShape(
                    RoundedRectangle(cornerRadius: 19.943, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19.943, style: .continuous)
                        .stroke(
                            Color(red: 0.33, green: 0.33, blue: 0.33),
                            lineWidth: 0.256
                        )
                )
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var flagContent: some View {
        switch kind {
        case .vietnam:
            ZStack {
                Color(red: 0.87, green: 0.13, blue: 0.12)

                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.92, blue: 0.2))
            }

        case .philippines:
            ZStack {
                VStack(spacing: 0) {
                    Color(red: 0.04, green: 0.29, blue: 0.72)
                    Color(red: 0.81, green: 0.08, blue: 0.2)
                }

                HStack(spacing: 0) {
                    SendFriendRequestTriangle()
                        .fill(Constants.White)
                        .frame(width: 13, height: 24)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            Color(red: 0.92, green: 0.74, blue: 0.18)
                        )
                        .padding(.leading, 4)

                    Spacer(minLength: 0)
                }
            }

        case .peru:
            HStack(spacing: 0) {
                Color(red: 0.81, green: 0.08, blue: 0.2)
                Constants.White
                Color(red: 0.81, green: 0.08, blue: 0.2)
            }

        case .argentina:
            ZStack {
                HStack(spacing: 0) {
                    Color(red: 0.47, green: 0.73, blue: 0.95)
                    Constants.White
                    Color(red: 0.47, green: 0.73, blue: 0.95)
                }

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color(red: 0.92, green: 0.74, blue: 0.18))
            }

        case .brazil:
            ZStack {
                Color(red: 0.13, green: 0.64, blue: 0.27)

                SendFriendRequestDiamond()
                    .fill(Color(red: 0.95, green: 0.84, blue: 0.18))
                    .frame(width: 14, height: 14)

                Circle()
                    .fill(Color(red: 0.11, green: 0.29, blue: 0.73))
                    .frame(width: 7.6, height: 7.6)

                Capsule()
                    .fill(Constants.White.opacity(0.8))
                    .frame(width: 7, height: 1.2)
                    .rotationEffect(.degrees(-15))
            }

        case .nigeria:
            HStack(spacing: 0) {
                Color(red: 0.0, green: 0.57, blue: 0.37)
                Constants.White
                Color(red: 0.0, green: 0.57, blue: 0.37)
            }
        }
    }
}

private struct SendFriendRequestTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SendFriendRequestDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct SendFriendRequestAvatarBadge: View {
    var ringPhrase: String = "CATTIE OI - MEMBER SINCE 2025"
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
                            color: Color(red: 1, green: 0.59, blue: 0.08),
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
                SendFriendRequestCircularTextGlyphs(
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
            withAnimation(
                .linear(duration: 30).repeatForever(autoreverses: false)
            ) {
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

private struct SendFriendRequestCircularTextGlyphs: View {
    let text: String
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        SendFriendRequestCircularTextRenderer(text: text, radius: radius)
            .frame(width: size, height: size)
    }
}

private struct SendFriendRequestCircularTextRenderer: UIViewRepresentable {
    let text: String
    let radius: CGFloat

    func makeUIView(context: Context)
        -> SendFriendRequestCircularTextDrawingView
    {
        let view = SendFriendRequestCircularTextDrawingView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(
        _ uiView: SendFriendRequestCircularTextDrawingView,
        context: Context
    ) {
        uiView.configuration = .init(text: text, radius: radius)
    }
}

private final class SendFriendRequestCircularTextDrawingView: UIView {
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
            let baseTotalWidth = characters.reduce(CGFloat.zero) {
                partial,
                character in
                partial + characterWidth(String(character), font: font)
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
        let startAngle =
            -CGFloat.pi / 2 - (totalArcLength / (2 * configuration.radius))
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

#Preview {
    SendFriendRequestView(friendCode: "preview123")
}
