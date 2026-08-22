//
//  PlanDetailVieww.swift
//  OnePlan
//
//  Created by ken on 11/3/26.
//

import MapKit
import SwiftUI

struct PlanDetailView: View {
    let tripId: Int
    let planItem: PlanItemDto
    let siblingPlanItems: [PlanItemDto]
    let service: TripDetailService
    let members: [TripMemberDto]
    // See StableDismiss: avoids the iOS-<26 NavigationStack relayout re-render loop
    // that froze the app when this view was pushed from the trip plan tab.
    @State private var stableDismiss = StableDismiss()
    @State private var voicePlaybackService = PlanVoicePlaybackService()
    @State private var currentPlanId: Int
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = String(localized: "Failed to delete plan.")
    @State private var isShowingEditPlan = false
    @State private var isShowingLocationDetail = false

    init(
        tripId: Int,
        planItem: PlanItemDto,
        siblingPlanItems: [PlanItemDto],
        service: TripDetailService,
        members: [TripMemberDto]
    ) {
        self.tripId = tripId
        self.planItem = planItem
        self.siblingPlanItems = siblingPlanItems
        self.service = service
        self.members = members
        self._currentPlanId = State(initialValue: Int(planItem.id))
    }

    private var currentPlanItem: PlanItemDto {
        // Read from the source of truth first, then fall back to the init-time snapshot.
        service.allPlanItems.first(where: { Int($0.id) == currentPlanId })
            ?? siblingPlanItems.first(where: { Int($0.id) == currentPlanId })
            ?? planItem
    }

    private var navigationPlanItems: [PlanItemDto] {
        siblingPlanItems.sorted { lhs, rhs in
            let lhsMinutes = minutesSinceMidnight(lhs.startTime)
            let rhsMinutes = minutesSinceMidnight(rhs.startTime)

            if lhsMinutes != rhsMinutes {
                return lhsMinutes < rhsMinutes
            }

            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.id < rhs.id
        }
    }

    private var planTitle: String {
        let trimmed = currentPlanItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Plan") : trimmed
    }

    private var planTimeAndDate: String {
        let time = textOrNil(currentPlanItem.startTime)
        let isPlanningMode = service.trip?.status.value1 == .PLANNING

        let date: String? = if isPlanningMode {
            // Planning mode: prefer dayNumber
            if let dayNum = currentPlanItem.dayNumber {
                String(localized: "Day \(Int(dayNum))")
            } else if let planDate = currentPlanItem.planDate {
                formattedPlanDate(planDate)
            } else {
                nil
            }
        } else {
            // Ongoing/other modes: prefer planDate
            if let planDate = currentPlanItem.planDate {
                formattedPlanDate(planDate)
            } else if let dayNum = currentPlanItem.dayNumber {
                String(localized: "Day \(Int(dayNum))")
            } else {
                nil
            }
        }

        switch (time, date) {
        case let (time?, date?):
            return String(localized: "\(time) - \(date)", comment: "%1$@ = time, %2$@ = date")
        case let (time?, nil):
            return time
        case let (nil, date?):
            return date
        default:
            return String(localized: "Not set")
        }
    }

    private var planLocation: String {
        textOrNil(currentPlanItem.location) ?? String(localized: "Not set")
    }

    private var locationName: String {
        textOrNil(currentPlanItem.location) ?? planTitle
    }

    private var hasLocationCoordinate: Bool {
        currentPlanItem.latitude != nil && currentPlanItem.longitude != nil
    }

    private var locationCoordinate: CLLocationCoordinate2D? {
        guard let latitude = currentPlanItem.latitude,
              let longitude = currentPlanItem.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func openDirections() {
        guard let coordinate = locationCoordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = locationName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private var planWhoJoin: String {
        if currentPlanItem.members.isEmpty {
            return String(localized: "No one")
        }
        if currentPlanItem.members.count == 1 {
            return currentPlanItem.members[0].displayName
        }
        // Pluralized in the String Catalog by the count argument.
        return String(localized: "\(currentPlanItem.members.count) members")
    }

    private var planMessage: String {
        textOrNil(currentPlanItem.description) ?? String(localized: "No message")
    }

    private var planVoiceDuration: String? {
        guard let durationSeconds = currentPlanItem.voiceDuration else { return nil }
        let totalSeconds = Int(durationSeconds)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private var planVoiceSource: String? {
        textOrNil(currentPlanItem.voiceUrl)
    }

    private func goToPreviousPlan() {
        guard let index = navigationPlanItems.firstIndex(where: { Int($0.id) == currentPlanId }),
              index > 0 else { return }
        currentPlanId = Int(navigationPlanItems[index - 1].id)
    }

    private func goToNextPlan() {
        guard let index = navigationPlanItems.firstIndex(where: { Int($0.id) == currentPlanId }),
              index < navigationPlanItems.count - 1 else { return }
        currentPlanId = Int(navigationPlanItems[index + 1].id)
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .center, spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    // Sub-Header
                    Text("Plan name")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.ContentB)

                }
                .padding(0)
                .frame(maxWidth: .infinity, alignment: .bottom)

                HStack(alignment: .center, spacing: 3) {
                    // Big Number
                    Text(planTitle)
                      .font(Font.custom("Be Vietnam Pro", size: 36))
                      .multilineTextAlignment(.center)
                      .foregroundColor(Constants.ContentB)
                }
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
            
            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    PlanDetailActionItem(
                        label: "Edit",
                        icon: "pencil",
                        iconColor: Constants.ContentB,
                        backgroundColor: Constants.OnSurface
                    ) {
                        isShowingEditPlan = true
                    }

//                    PlanDetailActionItem(
//                        label: "Send",
//                        icon: "square.and.arrow.up",
//                        iconColor: Constants.ContentB,
//                        backgroundColor: Constants.OnSurface
//                    ) { }

                    PlanDetailActionItem(
                        label: "Delete",
                        icon: "trash",
                        iconColor: Color(red: 1, green: 0.35, blue: 0.35),
                        backgroundColor: Color(red: 0.99, green: 0.91, blue: 0.91)
                    ) {
                        showDeleteConfirm = true
                    }
                    .disabled(service.isDeletingPlanItem)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                PlanDetailHistoryCard(
                    planTimeAndDate: planTimeAndDate,
                    locationCoordinate: locationCoordinate,
                    locationName: locationName,
                    onDirectionTapped: openDirections,
                    location: planLocation,
                    whoJoin: planWhoJoin,
                    message: planMessage,
                    voiceDuration: planVoiceDuration,
                    hasVoice: planVoiceSource != nil,
                    isVoiceLoading: voicePlaybackService.isLoading,
                    isVoicePlaying: voicePlaybackService.isPlaying,
                    onVoiceTapped: {
                        guard let source = planVoiceSource else { return }
                        Task {
                            await voicePlaybackService.togglePlayback(for: source)
                        }
                    },
                    onLocationTapped: hasLocationCoordinate
                        ? { isShowingLocationDetail = true }
                        : nil
                )
                    .padding(.horizontal)
                
                PlanDetailPrevNextStrip(
                    onPrev: goToPreviousPlan,
                    onNext: goToNextPlan
                )
            }
            .frame(maxWidth: .infinity)
        }
        .alert(
            "Audio Error",
            isPresented: Binding(
                get: { voicePlaybackService.error != nil },
                set: { isPresented in
                    if !isPresented {
                        voicePlaybackService.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { voicePlaybackService.clearError() }
        } message: {
            Text(voicePlaybackService.error ?? String(localized: "Unable to play voice message."))
        }
        .overlay {
            Color.clear
                .allowsHitTesting(false)
                .alert("Delete plan?", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        guard !service.isDeletingPlanItem else { return }
                        let deletingPlan = currentPlanItem
                        Task {
                            let result = await service.deletePlanItem(
                                tripId: tripId,
                                planItemId: Int(deletingPlan.id)
                            )
                            switch result {
                            case .success:
                                voicePlaybackService.stop()
                                stableDismiss()
                            case .failure(let error):
                                deleteErrorMessage = error.localizedDescription
                                showDeleteError = true
                            }
                        }
                    }
                } message: {
                    Text("This plan will be permanently removed from the trip.")
                }
        }
        .overlay {
            Color.clear
                .allowsHitTesting(false)
                .alert("Delete failed", isPresented: $showDeleteError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(deleteErrorMessage)
                }
        }
        .onDisappear {
            voicePlaybackService.stop()
        }
        .onChange(of: currentPlanId) { _, _ in
            voicePlaybackService.stop()
            voicePlaybackService.clearError()
        }
        .navigationDestination(isPresented: $isShowingEditPlan) {
            PlanFormView(
                form: PlanFormModel(
                    mode: .edit(currentPlanItem),
                    tripId: tripId,
                    members: members,
                    isPlanningMode: service.trip?.status.value1 == .PLANNING,
                    service: service,
                    tripStartDate: PlanFormDateParser.parseTripStartDate(service.trip?.startDate),
                    initialDayNumber: currentPlanItem.dayNumber.map { Int($0) }
                ),
                service: service
            )
        }
        .navigationDestination(isPresented: $isShowingLocationDetail) {
            if let latitude = currentPlanItem.latitude,
               let longitude = currentPlanItem.longitude {
                LocationDetailView(
                    initialLocationName: textOrNil(currentPlanItem.location) ?? planTitle,
                    initialLocationAddress: textOrNil(currentPlanItem.address) ?? "",
                    initialLatitude: latitude,
                    initialLongitude: longitude,
                    showsAddToPlan: false
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .background(Constants.Background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .captureStableDismiss(stableDismiss)
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

    private func minutesSinceMidnight(_ startTime: String?) -> Int {
        guard let startTime = textOrNil(startTime) else { return Int.max }
        let parts = startTime.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return Int.max
        }
        return hour * 60 + minute
    }
}

private struct PlanDetailActionItem: View {
    let label: LocalizedStringKey
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(iconColor)
                    }

                Text(label)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .kerning(-0.6)
                    .foregroundStyle(Constants.ContentB)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PlanDetailHistoryCard: View {
    let planTimeAndDate: String
    let locationCoordinate: CLLocationCoordinate2D?
    let locationName: String
    let onDirectionTapped: () -> Void
    let location: String
    let whoJoin: String
    let message: String
    let voiceDuration: String?
    let hasVoice: Bool
    let isVoiceLoading: Bool
    let isVoicePlaying: Bool
    let onVoiceTapped: () -> Void
    let onLocationTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            PlanDetailHistoryRow(title: "Time") {
                Text(planTimeAndDate)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)
            }

            if let locationCoordinate {
                PlanDetailLocationMapCard(
                    locationName: locationName,
                    coordinate: locationCoordinate,
                    onDirectionTapped: onDirectionTapped
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                // Force fresh identity per coordinate so the map recenters and
                // the orbit Task restarts when the user navigates Prev/Next
                // between sibling plans (the card stays mounted, so onAppear
                // won't re-fire otherwise). CLLocationCoordinate2D isn't
                // Hashable — key on the doubles.
                .id("\(locationCoordinate.latitude),\(locationCoordinate.longitude)")
            }

            PlanDetailDivider()

            if let onLocationTapped {
                Button(action: onLocationTapped) {
                    PlanDetailHistoryRow(title: "Location") {
                        HStack(spacing: 4) {
                            Text(location)
                                .font(Font.custom("Be Vietnam Pro", size: 16))
                                .foregroundStyle(Constants.ContentB)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Constants.ContentM)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                PlanDetailHistoryRow(title: "Location") {
                    Text(location)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                }
            }

            PlanDetailDivider()

            PlanDetailHistoryRow(title: "Who join") {
                HStack(spacing: 4) {
                    Image(systemName: "person.3")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.ContentB)

                    Text(whoJoin)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                }
            }

            PlanDetailDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Message")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)

                    Spacer(minLength: 8)

                    if hasVoice || voiceDuration != nil {
                        Button(action: onVoiceTapped) {
                            PlanDetailAudioBadge(
                                durationText: voiceDuration ?? "--:--",
                                isPlaying: isVoicePlaying,
                                isLoading: isVoiceLoading
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasVoice || isVoiceLoading)
                        .opacity(hasVoice ? 1 : 0.55)
                        .accessibilityLabel(
                            isVoicePlaying ? "Pause voice message" : "Play voice message"
                        )
                        .accessibilityHint(
                            hasVoice
                                ? "Double tap to toggle playback"
                                : "Voice message unavailable"
                        )
                    }
                }

                Text(message)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            
        }
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct PlanDetailLocationMapCard: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D
    let onDirectionTapped: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(locationName)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .kerning(-0.32)
                    .foregroundStyle(Constants.White)
                    .lineLimit(1)
                    .padding(.leading, 8)

                Spacer(minLength: 8)

                Button(action: onDirectionTapped) {
                    Text("Direction")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .kerning(-0.28)
                        .foregroundStyle(Constants.White)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.15))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            PlanDetailMapPreview(
                coordinate: coordinate,
                markerTitle: locationName
            )
            .accessibilityHidden(true) // decorative, non-interactive map
        }
        .padding(8)
        .background(Color(red: 0.165, green: 0.604, blue: 0.973)) // #2A9AF8
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct PlanDetailMapPreview: View {
    let coordinate: CLLocationCoordinate2D
    let markerTitle: String

    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var currentMapHeading: CLLocationDirection = 0
    @State private var cameraOrbitTask: Task<Void, Never>?

    private let mapCameraDistance: CLLocationDistance = 900
    private let mapCameraPitch: CGFloat = 58
    private let cameraOrbitStepDuration: TimeInterval = 0.12
    private let cameraOrbitHeadingIncrement: CLLocationDirection = 1

    var body: some View {
        Map(position: $mapCameraPosition, interactionModes: []) {
            Marker(markerTitle, coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(maxWidth: .infinity)
        .frame(height: 120, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            currentMapHeading = 0
            mapCameraPosition = cameraPosition(heading: currentMapHeading)
            startCameraOrbit()
        }
        .onDisappear {
            stopCameraOrbit()
        }
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

private struct PlanDetailHistoryRow<Content: View>: View {
    let title: LocalizedStringKey
    let trailingContent: Content

    init(title: LocalizedStringKey, @ViewBuilder trailingContent: () -> Content) {
        self.title = title
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .kerning(-0.7)
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailingContent
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
    }
}

private struct PlanDetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Constants.DividerStroke)
            .frame(height: 1)
    }
}

private struct PlanDetailAudioBadge: View {
    let durationText: String
    let isPlaying: Bool
    let isLoading: Bool

    private let barHeights: [CGFloat] = [
        7, 9, 7, 8, 11, 8, 7, 9, 11, 9, 7, 9, 11, 9, 11, 9, 7
    ]

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Constants.BlueBase)
                .frame(width: 24, height: 24)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Constants.White)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Constants.White)
                    }
                }

            HStack(spacing: 1.6) {
                ForEach(barHeights.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Constants.BlueBase)
                        .frame(width: 1.8, height: barHeights[index])
                }
            }
            .frame(height: 13)

            Text(durationText)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .kerning(-0.6)
                .foregroundStyle(Constants.BlueBase)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Constants.DividerStroke)
        .clipShape(Capsule(style: .continuous))
    }
}

#Preview {
    let samplePlans: [PlanItemDto] = [
        .init(
            id: 1,
            tripId: 1,
            planDate: "2026-03-23",
            title: "Breakfast + Coffee",
            description: "Try egg coffee at the local cafe.",
            location: "District 1",
            latitude: 10.7769,
            longitude: 106.7009,
            startTime: "08:30",
            category: nil,

            voiceUrl: nil,
            voiceDuration: 72,
            sortOrder: 0,
            createdAt: "2026-03-23T00:00:00Z",
            members: []
        ),
        .init(
            id: 2,
            tripId: 1,
            planDate: "2026-03-23",
            title: "Museum Visit",
            description: "Buy tickets first.",
            location: "City Museum",
            startTime: "10:00",
            category: nil,

            voiceUrl: nil,
            voiceDuration: 45,
            sortOrder: 1,
            createdAt: "2026-03-23T00:00:00Z",
            members: []
        ),
    ]

    PlanDetailView(
        tripId: 1,
        planItem: samplePlans[0],
        siblingPlanItems: samplePlans,
        service: TripDetailService(),
        members: []
    )
        .background(Constants.Background.ignoresSafeArea())
}
