//
//  LoginView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct SplitBillAIPaywallView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            topBlurBackground
                .ignoresSafeArea(.all, edges: .top)
                .zIndex(1)

            bottomBackground
                .ignoresSafeArea(.all, edges: .bottom)

            VStack {
                Spacer()

                HStack(alignment: .center, spacing: 10) {
                    Image("appLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 33, height: 33)
                        .clipped()

                    // Nav Link
                    Text("One Plan")
                        .font(Font.custom("Be Vietnam Pro", size: 20))
                        .foregroundColor(.white)
                }

                VStack(alignment: .center, spacing: 12) {
                    Text("Split bill by AI")
                        .font(Font.custom("Be Vietnam Pro", size: 32))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .top)

                    Text(
                        "Assign spending based on the actual expenses of each member."
                    )
                    .font(Font.custom("Be Vietnam Pro", size: 13.40506))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.White)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .opacity(0.7)
                }
                .padding(.top, 60)
                .padding(.bottom, 20)
                .frame(width: 211.08887, alignment: .top)

                receiptHero

                Spacer()

                VStack(spacing: 16) {
                    PremiumFriendsCard()
                        .frame(maxWidth: 350)

                    UpgradeProButton()
                        .frame(maxWidth: 350)
                }

            }
            .zIndex(2)
        }
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 695, height: 695)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }

    private var bottomBackground: some View {
        Image("paywallBackground")
            .resizable()
            .scaledToFit()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var receiptHero: some View {
        ZStack {
            Image("receiptPlaceholder")
                .resizable()
                .frame(width: 280, height: 321.0947)
                .clipped()

            receiptChipCluster
        }
        .frame(width: 360, height: 330)
    }

    private var receiptChipCluster: some View {
        ZStack {
            FloatingReceiptChip(content: .tea)
                .offset(x: -125, y: -58)
                .rotationEffect(.degrees(7))

            FloatingReceiptChip(content: .ramen)
                .offset(x: 118, y: -92)
                .rotationEffect(.degrees(-8))

            FloatingReceiptChip(content: .soup)
                .offset(x: -122, y: 28)
                .rotationEffect(.degrees(-7))

            FloatingReceiptChip(content: .juice)
                .offset(x: 120, y: 20)
                .rotationEffect(.degrees(4))

            FloatingReceiptChip(content: .rice)
                .offset(x: 112, y: 114)
                .rotationEffect(.degrees(5))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReceiptChipContent {
    let item: String
    let quantity: Int?
    let price: String

    static let tea = ReceiptChipContent(item: "Tea", quantity: nil, price: "8,000đ")
    static let ramen = ReceiptChipContent(item: "Ramen", quantity: nil, price: "65,000đ")
    static let soup = ReceiptChipContent(item: "Soup", quantity: 3, price: "25,000đ")
    static let juice = ReceiptChipContent(item: "Juice", quantity: nil, price: "45,000đ")
    static let rice = ReceiptChipContent(item: "Rice", quantity: 2, price: "12,000đ")
}

private struct FloatingReceiptChip: View {
    let content: ReceiptChipContent

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(alignment: .center, spacing: 2) {
                Text(content.item)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)


                if let quantity = content.quantity {
                    ZStack {
                        Circle()
                            .fill(Constants.BlueAlpha16)

                        Text("\(quantity)")
                            .font(Font.beVietnamPro(9.6, weight: .semibold))
                            .foregroundStyle(Constants.BlueBase)
                            .tracking(-1.152)
                    }
                    .frame(width: 16, height: 16)
                }
            }

            Text(content.price)
                .font(Font.custom("SF Compact Rounded", size: 14).weight(.medium))
                .foregroundStyle(Constants.BlueBase)
                .tracking(-0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Constants.White)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8.2, x: 0, y: 1)
    }
}

private struct PremiumFriendsCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PremiumAvatarStackView()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("5 friends are already premium!")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)

                Text("Enhance your experience now.")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentL)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.White)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 17.9, x: 0, y: 0)
    }
}

private struct PremiumAvatarStackView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            avatar("avatarPlaceholder", x: 0, y: 4.4)
            avatar("avatarPlaceholder", x: 17.7, y: 0)
            avatar("avatarPlaceholder", x: 5.4, y: 17.7)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.34, green: 1.0, blue: 0.49),
                                Color(red: 0.01, green: 0.58, blue: 0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("+3")
                    .font(
                        Font.beVietnamPro(9.6, weight: .semibold)
                    )
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(Constants.Surface, lineWidth: 1.14)
            )
            .frame(width: 16, height: 16)
            .offset(x: 20, y: 15.5)
        }
        .frame(width: 40, height: 40, alignment: .topLeading)
    }

    private func avatar(_ imageName: String, x: CGFloat, y: CGFloat)
        -> some View
    {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 22.28, height: 22.28)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Constants.Surface, lineWidth: 2)
            )
            .offset(x: x, y: y)
    }
}

#Preview {
    SplitBillAIPaywallView()
}
