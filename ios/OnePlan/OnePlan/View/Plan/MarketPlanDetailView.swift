//
//  MarketPlanDetailView.swift
//  OnePlan
//
//  Created by Codex on 13/5/26.
//

import SwiftUI

struct MarketPlanDetailView: View {
    let planItem: PlanItemDto
    let imageUrls: [String]
    let dayLabel: String?

    @State private var isShowingLocationDetail = false

    private var planTitle: String {
        textOrNil(planItem.title) ?? "Untitled Plan"
    }

    private var timeAndDayText: String {
        let time = textOrNil(planItem.startTime)
        let date = dayLabel ?? planItem.planDate.flatMap(formattedPlanDate)

        switch (time, date) {
        case let (time?, date?):
            return "\(time) - \(date)"
        case let (time?, nil):
            return time
        case let (nil, date?):
            return date
        default:
            return "Not set"
        }
    }

    private var locationText: String {
        textOrNil(planItem.location) ?? "Not set"
    }

    private var addressText: String {
        textOrNil(planItem.address) ?? ""
    }

    private var descriptionText: String {
        textOrNil(planItem.description) ?? "No message"
    }

    private var hasLocationCoordinate: Bool {
        planItem.latitude != nil && planItem.longitude != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection

                VStack(alignment: .leading, spacing: 4) {
                    detailsCard

                    if !imageUrls.isEmpty {
                        MarketPlanDetailPhotoStrip(imageUrls: imageUrls)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(isPresented: $isShowingLocationDetail) {
            if let latitude = planItem.latitude,
               let longitude = planItem.longitude {
                LocationDetailView(
                    initialLocationName: locationText,
                    initialLocationAddress: addressText,
                    initialLatitude: latitude,
                    initialLongitude: longitude,
                    showsAddToPlan: false
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .background {
            ZStack(alignment: .top) {
                Color(Constants.Background)
                    .ignoresSafeArea()

                topBlurBackground
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .background(Constants.Background)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(planTitle)
                .font(Font.custom("Be Vietnam Pro", size: 36))
                .foregroundStyle(Constants.ContentB)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            MarketPlanDetailRow(title: "Time") {
                Text(timeAndDayText)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)
            }

            MarketPlanDetailDivider()

            if hasLocationCoordinate {
                Button {
                    isShowingLocationDetail = true
                } label: {
                    locationRowContent(showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                locationRowContent(showsChevron: false)
            }

            MarketPlanDetailDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Message")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)

                Text(descriptionText)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .background(Constants.Surface)
        .cornerRadius(16)
    }

    private func locationRowContent(showsChevron: Bool) -> some View {
        MarketPlanDetailRow(title: "Location") {
            HStack(spacing: 4) {
                Text(locationText)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Constants.ContentM)
                }
            }
        }
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1)))
            .frame(width: 385, height: 385)
            .blur(radius: 60)
            .offset(y: -280)
            .allowsHitTesting(false)
    }

    private func textOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedPlanDate(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Parse the wire string with a fixed POSIX formatter…
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        if let date = parser.date(from: trimmed) {
            return DisplayFormatters.date(date)  // …render for DISPLAY in the current locale.
        }
        return trimmed
    }
}

private struct MarketPlanDetailPhoto: HeroLightboxItem {
    let id: Int
    let urlString: String
}

private struct MarketPlanDetailPhotoStrip: View {
    let imageUrls: [String]

    @State private var config: HeroLightboxConfig<MarketPlanDetailPhoto> = .init()

    private var photos: [MarketPlanDetailPhoto] {
        imageUrls.enumerated().map { index, urlString in
            MarketPlanDetailPhoto(id: index, urlString: urlString)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos (\(photos.count)/5)")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(photos, id: \.id) { photo in
                        Rectangle()
                            .foregroundStyle(.clear)
                            .overlay {
                                GeometryReader { proxy in
                                    let rect = proxy.frame(in: .global)
                                    let updatedRect: CGRect? = config.selectedItem == photo ? rect : nil

                                    thumbnail(for: photo)
                                        .opacity(config.selectedItem == photo ? 0 : 1)
                                        .frame(width: 112, height: 112)
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                        .contentShape(.rect)
                                        .onTapGesture {
                                            config.selectedItem = photo
                                            config.sourceLocation = rect
                                            withoutAnimation {
                                                config.showFullScreenCover = true
                                            }
                                        }
                                        .onChange(of: updatedRect) { _, newValue in
                                            if let newValue {
                                                config.sourceLocation = newValue
                                            }
                                        }
                                }
                            }
                            .frame(width: 112, height: 112)
                            .clipped()
                            .contentShape(.rect)
                    }
                }
                .scrollTargetLayout()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.Surface)
        .cornerRadius(16)
        .scrollPosition(id: $config.sourceScrollID)
        .fullScreenCover(isPresented: $config.showFullScreenCover) {
            config.selectedItem = nil
        } content: {
            HeroLightboxDetailView(
                config: $config,
                data: photos
            ) { photo, isExpanded, _, _ in
                CachedRemoteImage(url: URL(string: photo.urlString)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } overlay: { _, _, _, dismiss in
                VStack {
                    HStack {
                        Spacer()

                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Constants.White)
                                .frame(width: 40, height: 40)
                                .background(Constants.Black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 54)
                    .padding(.horizontal, 18)

                    Spacer()
                }
            }
        }
        .onChange(of: config.selectedItem) { oldValue, newValue in
            if let newValue, oldValue != nil {
                config.sourceScrollID = newValue.id
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for photo: MarketPlanDetailPhoto) -> some View {
        CachedRemoteImage(
            url: URL(string: photo.urlString),
            targetSize: CGSize(width: 120, height: 120)
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Constants.Neutral100)
        }
    }
}

private struct MarketPlanDetailRow<Content: View>: View {
    let title: LocalizedStringKey
    let trailingContent: Content

    init(title: LocalizedStringKey, @ViewBuilder trailingContent: () -> Content) {
        self.title = title
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailingContent
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

private struct MarketPlanDetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Constants.DividerStroke)
            .frame(height: 1)
    }
}

#Preview {
    NavigationStack {
        MarketPlanDetailView(
            planItem: .init(
                id: 1,
                tripId: 1,
                planDate: "2026-03-26",
                title: "Sunrise viewpoint",
                description: "Bring a jacket and arrive early for the best view.",
                location: "Da Lat hills",
                startTime: "06:00",
                category: nil,
                voiceUrl: nil,
                voiceDuration: nil,
                sortOrder: 0,
                createdAt: "2026-03-26T00:00:00Z",
                members: []
            ),
            imageUrls: [
                "https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?w=900",
                "https://images.pexels.com/photos/3225517/pexels-photo-3225517.jpeg?w=900",
            ],
            dayLabel: "Day 1"
        )
    }
}
