//
//  TripEndHistoryView.swift
//  OnePlan
//
//  Created by ken on 25/3/26.
//

import MapKit
import SwiftUI
import UIKit

struct TripEndHistory: View {
    let service: TripDetailService
    let tripId: Int
    /// When true, the History section is the vault ledger (web3), not expenses.
    var usesVaultHistory: Bool = false
    var onVaultSendAgain: (String) -> Void = { _ in }

    @State private var downloadService = PhotoDownloadService()
    @State private var isShowingPermissionDenied = false
    @State private var isShowingDownloadError = false
    @State private var downloadErrorMessage = ""
    @State private var downloadCompleted = false
    @State private var downloadSavedCount = 0
    @State private var isShowingSellPlan = false
    @State private var isShowingRatingSheet = false
    @State private var ratingSubmitError: String?
    @State private var isShowingRatingError = false
    @State private var localUserRating: Int?
    @State private var ratingService = MarketplaceRatingService()

    /// Figma `4013:12858` Upload plan fill `#48B9FF` (sky), not brand BlueBase.
    private static let uploadPlanTint = Color(
        red: 72 / 255, green: 185 / 255, blue: 255 / 255
    )

    private func locationLabel(
        _ location: Components.Schemas.TripLocationDto
    ) -> String {
        [location.cityName, location.countryName]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var effectiveUserRating: Int? {
        if let local = localUserRating { return local }
        if let remote = service.trip?.userMarketplaceRating { return Int(remote) }
        return nil
    }

    private var locationsText: String {
        String(
            localized: "\(service.allPlanItems.count) locations",
            comment: "Number of plan locations on the trip-end map; %lld = count"
        )
    }

    private var placesText: String {
        // Pluralized in the String Catalog by the count argument.
        String(localized: "\(service.allPlanItems.count) places", comment: "Number of places in a trip; %lld = count")
    }

    private var durationText: String {
        // Pluralized in the String Catalog by the count argument.
        String(localized: "\(computedDurationDays) days", comment: "Trip duration; %lld = number of days")
    }

    private var computedDurationDays: Int {
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parse(_ string: String?) -> Date? {
            guard let string, !string.isEmpty else { return nil }
            if let date = dateOnly.date(from: String(string.prefix(10))) {
                return date
            }
            return iso.date(from: string)
        }

        if let start = parse(service.trip?.startDate),
            let end = parse(service.trip?.endDate)
        {
            let components = Calendar.current.dateComponents(
                [.day], from: start, to: end
            )
            let days = (components.day ?? 0) + 1
            return max(days, 1)
        }

        let maxDay = service.allPlanItems
            .compactMap { $0.dayNumber }
            .map { Int($0) }
            .max() ?? 1
        return max(maxDay, 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TripEndHeroHeader(
                    coverImageUrl: service.trip?.coverImageUrl,
                    totalSpent: service.totalSpent,
                    unsettledPaymentCount: service.unsettledPaymentCount,
                    currency: Currency(from: service.trip?.currency.value1) ?? .VND,
                    // Figma End trip History shows the settle-up line under Total spent.
                    showsSettlementStatus: true
                )

                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Shared Album
                    if !service.photos.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 10) {
                                    Image("polarizedCamera")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 54, height: 54)
                                        .clipped()

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Shared album")
                                            .font(
                                                Font.custom(
                                                    "Be Vietnam Pro",
                                                    size: 14
                                                )
                                            )
                                            .foregroundColor(Constants.ContentB)

                                        Text(
                                            "\(service.photos.count) photos uploaded by all members."
                                        )
                                        .font(
                                            Font.custom("Be Vietnam Pro", size: 14)
                                        )
                                        .foregroundColor(Constants.ContentM)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .topLeading
                                        )
                                    }
                                    .padding(0)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .topLeading
                                    )

                                    PrimaryButton(
                                        title: downloadCompleted
                                            ? "Saved \(downloadSavedCount)"
                                            : downloadService.isDownloading
                                                ? "\(downloadService.completedCount)/\(downloadService.totalCount)"
                                                : "Download all"
                                    ) {
                                        Task {
                                            let allPhotos =
                                                service.hasMorePhotos
                                                ? await service.fetchAllPhotos(
                                                    tripId: tripId
                                                )
                                                : service.photos
                                            let result =
                                                await downloadService
                                                .downloadAllPhotos(
                                                    photos: allPhotos
                                                )
                                            switch result {
                                            case .success(let savedCount):
                                                downloadSavedCount = savedCount
                                                downloadCompleted = true
                                            case .permissionDenied:
                                                isShowingPermissionDenied = true
                                            case .failure(let msg):
                                                downloadErrorMessage = msg
                                                isShowingDownloadError = true
                                            }
                                        }
                                    }
                                    .disabled(
                                        downloadService.isDownloading
                                            || downloadCompleted
                                    )
                                }
                                .padding(.horizontal, 0)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                                .frame(maxWidth: .infinity, alignment: .center)

                                if downloadService.isDownloading {
                                    VStack(spacing: 8) {
                                        ProgressView(
                                            value: downloadService.progress
                                        )
                                        .tint(Constants.BlueBase)
                                        Text("Saving to camera roll...")
                                            .font(
                                                Font.custom(
                                                    "Be Vietnam Pro",
                                                    size: 12
                                                )
                                            )
                                            .foregroundColor(Constants.ContentM)
                                    }
                                    .padding(.horizontal, 8)
                                } else {
                                    SharedAlbumPreviewStack(
                                        photos: Array(service.photos.prefix(3))
                                    )
                                }
                            }
                            .padding(8)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 185,
                                maxHeight: 185,
                                alignment: .topLeading
                            )
                            .background(Constants.Surface)
                            .cornerRadius(24)
                        }
                        .padding(0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    // MARK: - Trip Plan
                    if let location = service.trip?.location?.value1,
                        let lat = location.latitude,
                        let lon = location.longitude
                    {
                        VStack(alignment: .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 10) {
                                    Image("signpost")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 54, height: 54)
                                        .clipped()

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Trip Plan")
                                            .font(
                                                Font.custom(
                                                    "Be Vietnam Pro", size: 14
                                                )
                                            )
                                            .foregroundColor(Constants.ContentB)

                                        Text("Sell this trip plan to market and earn more.")
                                            .font(Font.custom("Be Vietnam Pro", size: 14))
                                            .foregroundColor(Constants.ContentM)
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                    .padding(0)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .topLeading
                                    )

                                    if service.trip?.marketplaceListingId != nil {
                                        if let myRating = effectiveUserRating {
                                            PrimaryButton(
                                                title: "Rated ★ \(myRating)",
                                                tint: Self.uploadPlanTint,
                                                fillsWidth: false
                                            ) { }
                                                .disabled(true)
                                        } else {
                                            PrimaryButton(
                                                title: "Rate plan",
                                                tint: Self.uploadPlanTint,
                                                fillsWidth: false
                                            ) {
                                                isShowingRatingSheet = true
                                            }
                                        }
                                    } else {
                                        PrimaryButton(
                                            title: "Upload plan",
                                            tint: Self.uploadPlanTint,
                                            fillsWidth: false
                                        ) {
                                            isShowingSellPlan = true
                                        }
                                    }
                                }
                                .padding(.horizontal, 0)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                                .frame(maxWidth: .infinity, alignment: .center)

                                MapPreviewContainer(
                                    coordinate: CLLocationCoordinate2D(
                                        latitude: lat, longitude: lon
                                    ),
                                    markerTitle: location.cityName ?? "Trip",
                                    locationLabel: locationLabel(location),
                                    locationsText: locationsText
                                )
                            }
                            .padding(8)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 220,
                                alignment: .topLeading
                            )
                            .background(Constants.Surface)
                            .cornerRadius(24)
                        }
                        .padding(0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    // MARK: - History
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundColor(Constants.ContentM)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        if usesVaultHistory {
                            VaultHistoryView(
                                tripId: tripId,
                                members: service.trip?.members ?? [],
                                allowsEditing: false,
                                onSendAgain: onVaultSendAgain,
                                embedsInParentScroll: true
                            )
                        } else if !service.groupedHistory.isEmpty {
                            TripHistorySection(
                                groupedHistory: service.groupedHistory,
                                isLoading: false
                            )
                        }
                    }
                    .padding(0)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ScrollViewBackgroundClearer())
        .background(.clear)
        .scrollIndicators(.hidden)
        .alert("Photo Library Access", isPresented: $isShowingPermissionDenied) {
            Button("Open Settings") {
                if let settingsUrl = URL(
                    string: UIApplication.openSettingsURLString
                ) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "OnePlan needs permission to save photos to your camera roll. Please enable it in Settings."
            )
        }
        .alert("Download failed", isPresented: $isShowingDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadErrorMessage)
        }
        .alert("Rating failed", isPresented: $isShowingRatingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ratingSubmitError ?? String(localized: "Please try again"))
        }
        .navigationDestination(isPresented: $isShowingSellPlan) {
            UploadTripView(service: service, tripId: tripId)
        }
        .sheet(isPresented: $isShowingRatingSheet) {
            RatingTripBottomSheet(
                listingName: service.trip?.name ?? "",
                placesText: placesText,
                durationText: durationText,
                thumbnailUrl: service.trip?.coverImageUrl,
                onContinue: { rating in
                        guard let listingId = service.trip?.marketplaceListingId
                        else { return }
                        Task {
                            do {
                                _ = try await ratingService.submitRating(
                                    listingId: Int(listingId),
                                    rating: rating
                                )
                                localUserRating = rating
                            } catch {
                                ratingSubmitError = error.localizedDescription
                                isShowingRatingError = true
                            }
                        }
                    }
                )
        }
    }
}

private struct ScrollViewBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var currentView = uiView.superview
            while let view = currentView {
                if let scrollView = view as? UIScrollView {
                    scrollView.backgroundColor = .clear
                    return
                }
                currentView = view.superview
            }
        }
    }
}

private struct SharedAlbumPreviewStack: View {
    let photos: [TripPhotoDto]

    private static let rotations: [Angle] = [
        .degrees(-13.75), .degrees(9.52), .degrees(0),
    ]
    private static let offsets: [CGSize] = [
        CGSize(width: -56, height: 2),
        CGSize(width: -8, height: 3),
        CGSize(width: 40, height: 2),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Constants.Neutral50)

            ZStack {
                ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) {
                    index,
                    photo in
                    SharedAlbumPreviewCard(
                        imageUrl: photo.url,
                        rotation: Self.rotations[index]
                    )
                    .offset(Self.offsets[index])
                }
            }
            .offset(y: 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 95, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SharedAlbumPreviewCard: View {
    let imageUrl: String?
    let rotation: Angle

    var body: some View {
        Group {
            if let imageUrl, let url = URL(string: imageUrl) {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: 88, height: 108)
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Constants.Neutral50)
                }
            } else {
                Rectangle().fill(Constants.Neutral50)
            }
        }
        .frame(width: 88, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .inset(by: 0.7)
                .stroke(Constants.ContentM, lineWidth: 1.4)
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Constants.Black)
        )
        .rotationEffect(rotation)
    }
}

private struct MapPreviewContainer: View {
    let coordinate: CLLocationCoordinate2D
    let markerTitle: String
    var locationLabel: String = ""
    var locationsText: String = ""

    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var currentMapHeading: CLLocationDirection = 0
    @State private var cameraOrbitTask: Task<Void, Never>?

    private let mapCameraDistance: CLLocationDistance = 900
    private let mapCameraPitch: CGFloat = 58
    private let cameraOrbitStepDuration: TimeInterval = 0.12
    private let cameraOrbitHeadingIncrement: CLLocationDirection = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $mapCameraPosition, interactionModes: []) {
                Marker(markerTitle, coordinate: coordinate)
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(maxWidth: .infinity)
            .frame(height: 120, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)

            if !locationLabel.isEmpty || !locationsText.isEmpty {
                HStack(spacing: 6) {
                    if !locationLabel.isEmpty {
                        mapPill(locationLabel)
                    }
                    if !locationsText.isEmpty {
                        mapPill(locationsText)
                    }
                }
                .padding(8)
            }
        }
        .onAppear {
            currentMapHeading = 0
            mapCameraPosition = cameraPosition(heading: currentMapHeading)
            startCameraOrbit()
        }
        .onDisappear {
            stopCameraOrbit()
        }
    }

    private func mapPill(_ text: String) -> some View {
        Text(text)
            .font(Font.beVietnamPro(12))
            .foregroundStyle(Constants.ContentB)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Constants.White, in: Capsule())
    }

    private func cameraPosition(heading: CLLocationDirection)
        -> MapCameraPosition
    {
        .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: mapCameraDistance,
                heading: heading,
                pitch: mapCameraPitch
            )
        )
    }

    private func startCameraOrbit() {
        stopCameraOrbit()
        cameraOrbitTask = Task {
            while !Task.isCancelled {
                let nextHeading =
                    (currentMapHeading + cameraOrbitHeadingIncrement)
                    .truncatingRemainder(dividingBy: 360)
                await MainActor.run {
                    withAnimation(
                        .linear(duration: cameraOrbitStepDuration)
                    ) {
                        currentMapHeading = nextHeading
                        mapCameraPosition = cameraPosition(
                            heading: nextHeading
                        )
                    }
                }
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        cameraOrbitStepDuration * 1_000_000_000
                    )
                )
            }
        }
    }

    private func stopCameraOrbit() {
        cameraOrbitTask?.cancel()
        cameraOrbitTask = nil
    }
}

#Preview {
    TripEndHistory(service: TripDetailService(), tripId: 0)
}
