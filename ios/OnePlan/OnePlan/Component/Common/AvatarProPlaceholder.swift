//
//  AvatarProPlaceholder.swift
//  OnePlan
//
//  Created by ken on 6/4/26.
//

import SwiftUI

struct AvatarProPlaceholder: View {
    var size: CGFloat = 200
    var imageUrl: String? = nil
    var placeholderImageName: String = "avatarPlaceholder"
    var showBadge: Bool = true

    private var innerAvatarSize: CGFloat { size * 0.86 }  // 172 / 200
    private var outerShadowScale: CGFloat { size / 200 }
    private var badgeCornerRadius: CGFloat { max(size * 0.05, 3) }  // 10 / 200, min 3

    // Badge sizing with minimums for small avatars
    private var badgeFontSize: CGFloat { max(size * (20.079 / 200), 8) }
    private var badgeTracking: CGFloat { size * (-0.8032 / 200) }
    private var badgeHorizontalPadding: CGFloat { max(size * (8 / 200), 4) }
    private var badgeTopPadding: CGFloat { max(size * (8 / 200), 3) }
    private var badgeBottomPadding: CGFloat { max(size * (14 / 200), 5) }
    private var badgeBorderWidth: CGFloat { max(size * (2 / 200), 1) }

    var body: some View {
        Group {
            if showBadge {
                proAvatar
            } else {
                plainAvatar
            }
        }
    }

    private var plainAvatar: some View {
        avatarImage
            .frame(width: size, height: size)
            .clipShape(Circle())
    }

    private var proAvatar: some View {
        ZStack {
            Circle()
                .fill(Constants.White)

            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Constants.White.opacity(0.19), location: 0),
                            .init(
                                color: Color(red: 0 / 255, green: 80 / 255, blue: 217 / 255),
                                location: 0.83582
                            ),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            avatarImage
                .frame(width: innerAvatarSize, height: innerAvatarSize)
                .clipShape(Circle())
        }
        .overlay(alignment: .bottom) {
            proBadge
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            ZStack {
                Circle()
                    .stroke(
                        Color(red: 77 / 255, green: 205 / 255, blue: 1).opacity(0.9),
                        lineWidth: 6 * outerShadowScale
                    )
                    .blur(radius: 3.5 * outerShadowScale)
                    .offset(y: -2 * outerShadowScale)
                    .clipShape(Circle())

                Circle()
                    .stroke(Constants.White.opacity(0.95), lineWidth: 4 * outerShadowScale)
                    .blur(radius: 2.2 * outerShadowScale)
                    .offset(
                        x: -1.6 * outerShadowScale,
                        y: -1.6 * outerShadowScale
                    )
                    .clipShape(Circle())
            }
        }
        .shadow(
            color: Color(red: 100 / 255, green: 146 / 255, blue: 1, opacity: 0.39),
            radius: 3.05 * outerShadowScale,
            x: 0,
            y: 3 * outerShadowScale
        )
        .shadow(
            color: Color(red: 149 / 255, green: 209 / 255, blue: 1, opacity: 0.25),
            radius: 5.7 * outerShadowScale,
            x: 0,
            y: 13 * outerShadowScale
        )
        .shadow(
            color: Constants.Black.opacity(0.34),
            radius: 14.1665 * outerShadowScale,
            x: -4.393 * outerShadowScale,
            y: 17.571 * outerShadowScale
        )
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let imageUrl, let url = URL(string: imageUrl) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: innerAvatarSize, height: innerAvatarSize)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(placeholderImageName)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            Image(placeholderImageName)
                .resizable()
                .scaledToFill()
        }
    }

    private var proBadge: some View {
        Text("PRO")
            .font(Font.beVietnamPro(badgeFontSize, weight: .heavy))
            .tracking(badgeTracking)
            .foregroundStyle(Constants.BlueBase)
            .padding(.horizontal, badgeHorizontalPadding)
            .padding(.top, badgeTopPadding)
            .padding(.bottom, badgeBottomPadding)
            .background {
                TopRoundedBadgeShape(cornerRadius: badgeCornerRadius)
                    .fill(Constants.White)
                    .overlay {
                        TopAndSideBorderShape(cornerRadius: badgeCornerRadius)
                            .stroke(Constants.BlueBase, lineWidth: badgeBorderWidth)
                    }
            }
    }
}

private struct TopRoundedBadgeShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width / 2, rect.height))

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: radius),
            control: CGPoint(x: rect.width, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()

        return path
    }
}

private struct TopAndSideBorderShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width / 2, rect.height))

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: radius),
            control: CGPoint(x: rect.width, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))

        return path
    }
}

#Preview {
    ZStack {
        Constants.Black
            .ignoresSafeArea()
        AvatarProPlaceholder()
    }
}
