//
//  BuyVideoExtractionQuotaBottomSheet.swift
//  OnePlan
//
//  Created by ken on 16/5/26.
//

import SwiftUI

struct VideoExtractionQuotaPackage: Identifiable, Hashable {
    let id: String
    let title: String
    let priceDetail: String
    let badge: String?
    let footnote: String?
    let ctaTitle: String
}

struct BuyVideoExtractionQuotaBottomSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackageID: String
    @State private var scrollPositionID: String?
    @State private var isSelectionHapticReady = false

    var packages: [VideoExtractionQuotaPackage]
    var onPurchase: (VideoExtractionQuotaPackage) -> Void

    private static let sheetHeight: CGFloat = 550
    private static let cardWidth: CGFloat = 239
    private static let carouselHorizontalPadding: CGFloat = 22
    private static let finalCardPeek: CGFloat = 72
    private static let termsAndConditionsURL = URL(
        string: "https://oneplan.space/termandconditions"
    )
    private static let privacyPolicyURL = URL(
        string: "https://oneplan.space/privacy-policy"
    )
    private static let eulaURL = URL(
        string:
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )
    private static let defaultPackages: [VideoExtractionQuotaPackage] = [
        VideoExtractionQuotaPackage(
            id: "oneplan.video_scan_1",
            title: String(localized: "1 video scan"),
            priceDetail: String(localized: "25,000đ each"),
            badge: nil,
            footnote: String(localized: "Most popular"),
            ctaTitle: String(localized: "Get 1 scan for 25,000đ")
        ),
        VideoExtractionQuotaPackage(
            id: "oneplan.video_scan_30",
            title: String(localized: "30 video scans"),
            priceDetail: String(localized: "11,634đ each"),
            badge: String(localized: "Save 53%"),
            footnote: String(localized: "Best value"),
            ctaTitle: String(localized: "Get 30 scans")
        ),
        VideoExtractionQuotaPackage(
            id: "oneplan.video_scan_15",
            title: String(localized: "15 video scans"),
            priceDetail: String(localized: "14,600đ each"),
            badge: String(localized: "Save 41%"),
            footnote: nil,
            ctaTitle: String(localized: "Get 15 scans")
        ),
        VideoExtractionQuotaPackage(
            id: "oneplan.video_scan_5",
            title: String(localized: "5 video scans"),
            priceDetail: String(localized: "69,000đ"),
            badge: String(localized: "Save 36%"),
            footnote: nil,
            ctaTitle: String(localized: "Get 5 scans")
        ),
    ]

    init(
        packages: [VideoExtractionQuotaPackage] = Self.defaultPackages,
        initiallySelectedPackageID: String? = nil,
        onPurchase: @escaping (VideoExtractionQuotaPackage) -> Void = { _ in }
    ) {
        self.packages = packages
        self.onPurchase = onPurchase
        _selectedPackageID = State(
            initialValue: initiallySelectedPackageID ?? packages.first?.id ?? ""
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if packages.isEmpty {
                        unavailablePackagesState
                    } else {
                        quotaPackageCarousel
                    }
                }
                .padding(.top, 50)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Neutral50)
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(logoAssetName(for: selectedPackageID))
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text("Discover more hidden gems\nby social videos")
                    .font(.beVietnamPro(24, weight: .medium))
                    .foregroundStyle(Constants.Neutral950)
                    .tracking(-0.96)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Unlock more video scans to instantly detect places from videos and save them into your favorite lists."
                )
                .font(.custom("Be Vietnam Pro", size: 13))
                .foregroundStyle(Constants.Neutral600)
                .tracking(-0.65)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
    }

    private var unavailablePackagesState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Constants.ContentM)

            Text("Video scan packs are unavailable")
                .font(.beVietnamPro(16, weight: .semibold))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.48)

            Text("Please check your connection and try again.")
                .font(.custom("Be Vietnam Pro", size: 13))
                .foregroundStyle(Constants.Neutral600)
                .tracking(-0.39)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.Neutral100, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 22)
    }

    private var quotaPackageCarousel: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(packages) { package in
                        quotaPackageCard(
                            package,
                            isSelected: package.id == selectedPackageID
                        )
                        .id(package.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 5)
                .padding(.leading, Self.carouselHorizontalPadding)
                .padding(
                    .trailing,
                    trailingCarouselPadding(for: proxy.size.width)
                )
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPositionID)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .frame(height: 141)
        .onAppear {
            let initialID =
                packages.contains(where: { $0.id == selectedPackageID })
                ? selectedPackageID
                : packages.first?.id

            if let initialID {
                selectedPackageID = initialID
                scrollPositionID = initialID
            }
            DispatchQueue.main.async {
                isSelectionHapticReady = true
            }
        }
        .onChange(of: packages.map(\.id)) { _, _ in
            let fallbackID = packages.first?.id
            if packages.contains(where: { $0.id == selectedPackageID }) {
                scrollPositionID = selectedPackageID
            } else if let fallbackID {
                selectedPackageID = fallbackID
                scrollPositionID = fallbackID
            }
        }
        .onChange(of: scrollPositionID) { _, newValue in
            guard let newValue, selectedPackageID != newValue else { return }
            triggerSelectionHaptic()
            withAnimation(selectionAnimation) {
                selectedPackageID = newValue
            }
        }
        .onChange(of: selectedPackageID) { _, newValue in
            guard scrollPositionID != newValue else { return }
            triggerSelectionHaptic()
            withAnimation(selectionAnimation) {
                scrollPositionID = newValue
            }
        }
    }

    private func trailingCarouselPadding(for width: CGFloat) -> CGFloat {
        max(
            Self.carouselHorizontalPadding,
            width - Self.cardWidth - Self.carouselHorizontalPadding
                - Self.finalCardPeek
        )
    }

    private func triggerSelectionHaptic() {
        guard isSelectionHapticReady else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func quotaPackageCard(
        _ package: VideoExtractionQuotaPackage,
        isSelected: Bool
    ) -> some View {
        Button {
            withAnimation(selectionAnimation) {
                selectedPackageID = package.id
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        isSelected ? Constants.BlueBase : Constants.Neutral100
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(package.title)
                        .font(
                            .beVietnamPro(16, weight: .semibold)
                        )
                        .foregroundStyle(
                            isSelected ? Constants.White : Constants.ContentB
                        )
                        .tracking(-0.48)
                        .lineLimit(1)

                    Text(package.priceDetail)
                        .font(.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(
                            isSelected ? Constants.White : Constants.ContentB
                        )
                        .tracking(-0.42)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let footnote = package.footnote {
                        Text(footnote)
                            .font(.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(
                                isSelected
                                    ? Constants.White : Constants.ContentM
                            )
                            .tracking(-0.42)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .padding(.trailing, 54)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Constants.White)
                        .frame(width: 20, height: 20)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let badge = package.badge {
                    saveBadge(badge)
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                }
            }
            .frame(width: Self.cardWidth, height: 131)
            .contentShape(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .scaleEffect(isSelected ? 1.04 : 1)
            .zIndex(isSelected ? 1 : 0)
            .animation(selectionAnimation, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
    }

    private func saveBadge(_ badge: String) -> some View {
        Text(badge)
            .font(.custom("Be Vietnam Pro", size: 14))
            .foregroundStyle(Constants.White)
            .tracking(-0.7)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: 33)
            .background(saveBadgeBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Constants.White, lineWidth: 1)
            )
            .shadow(
                color: Color(red: 0.39, green: 0.57, blue: 1).opacity(0.39),
                radius: 1.94,
                x: 0,
                y: 1.9
            )
            .shadow(
                color: Color(red: 0.58, green: 0.82, blue: 1).opacity(0.25),
                radius: 3.62,
                x: 0,
                y: 8.25
            )
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? .none : .snappy(duration: 0.2, extraBounce: 0)
    }

    private var saveBadgeBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.28, green: 0.42, blue: 1).opacity(0.1),
                Color(red: 0, green: 0.31, blue: 0.85),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(termsMessage)
                .tracking(-0.42)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard let selectedPackage else { return }
                onPurchase(selectedPackage)
                dismiss()
            } label: {
                Text(selectedPackage?.ctaTitle ?? "Scan packs unavailable")
                    .font(.custom("Be Vietnam Pro", size: 17))
                    .foregroundStyle(Constants.White)
                    .tracking(-0.68)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Constants.Black, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .disabled(selectedPackage == nil)
            .opacity(selectedPackage == nil ? 0.45 : 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.White)
        .shadow(color: .black.opacity(0.25), radius: 13.25, x: 0, y: 0)
    }

    private var selectedPackage: VideoExtractionQuotaPackage? {
        packages.first { $0.id == selectedPackageID }
    }

    private func logoAssetName(for packageID: String) -> String {
        guard let creditCount = packageID.split(separator: "_").last else {
            return "1VideoScan"
        }
        return "\(creditCount)VideoScan"
    }

    private var termsMessage: AttributedString {
        var message = AttributedString(
            "By purchasing, you agree to this transaction and our Privacy Policy, Terms of Service &  Terms of EULA"
        )
        message.font = .custom("Be Vietnam Pro", size: 16)
        message.foregroundColor = Constants.ContentM

        linkText("Privacy Policy", in: &message, to: Self.privacyPolicyURL)
        linkText(
            "Terms of Service",
            in: &message,
            to: Self.termsAndConditionsURL
        )
        linkText("Terms of EULA", in: &message, to: Self.eulaURL)

        return message
    }

    private func linkText(
        _ text: String,
        in message: inout AttributedString,
        to url: URL?
    ) {
        guard let url, let range = message.range(of: text) else { return }
        message[range].font = .beVietnamPro(14, weight: .medium)
        message[range].foregroundColor = Constants.Neutral950
        message[range].underlineStyle = .single
        message[range].link = url
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            BuyVideoExtractionQuotaBottomSheet()
        }
}
