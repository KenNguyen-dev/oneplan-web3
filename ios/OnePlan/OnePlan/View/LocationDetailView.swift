//
//  LocationDetailView.swift
//  OnePlan
//
//  Created by ken on 9/3/26.
//

import MapKit
import SwiftUI

struct LocationDetailView: View {
    let initialLocationName: String
    let initialLocationAddress: String
    let initialLatitude: Double
    let initialLongitude: Double
    var userLocation: CLLocation? = nil
    var showsAddToPlan: Bool = true
    var addToPlanButtonTitle: String = String(localized: "Add to plan")
    var onAddToPlan:
        (_ name: String, _ address: String, _ lat: Double, _ lng: Double) ->
            Void = { _, _, _, _ in }
    var onDismiss: () -> Void = {}
    /// When non-nil, the view runs in **picker mode**: the map is the host and
    /// the search/board picker floats over it as a native morphing sheet
    /// (search ↔ detail). When nil, the view is the read-only standalone map
    /// detail with its custom draggable sheet.
    var pickerConfig: LocationPickerConfig? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var isPickerMode: Bool { pickerConfig != nil }

    // Current displayed location (can change when POI is tapped)
    @State private var displayedName: String = ""
    @State private var displayedAddress: String = ""
    @State private var displayedLatitude: Double = 0
    @State private var displayedLongitude: Double = 0

    private var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: displayedLatitude,
            longitude: displayedLongitude
        )
    }

    // Map selection for POIs
    @State private var selectedMapFeature: MapFeature?
    @State private var selectedPOICoordinate: CLLocationCoordinate2D?
    @State private var selectedPOIName: String?

    @State private var selectedTab: LocationDetailTab = .top
    @State private var sheetMode: LocationDetailSheetMode = .medium
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var currentMapHeading: CLLocationDirection = 0
    @State private var cameraOrbitTask: Task<Void, Never>?
    @State private var contentScrollOffset: CGFloat = 0
    @State private var sheetContentHeight: CGFloat = 1
    @State private var activeSheetDrag: CGFloat = 0
    @State private var planAddCount: Int?
    @State private var lastDragHapticZone: Int = 0
    @State private var lastHapticDragPosition: CGFloat = 0
    @State private var deviceHeading = DeviceHeadingService()
    @State private var mapSearchService = MapSearchService()
    @State private var isShowingDirections = false
    @State private var directionsTransportMode: LocationDirectionsTransportMode = .walking

    // MARK: Picker mode (native morphing sheet)
    @State private var sheetContent: LocationSheetContent = .search
    @State private var selectedDetent: PresentationDetent = .fraction(0.5)
    @State private var isSheetPresented = true
    /// The last single place reported by the picker — used only to recover the
    /// POI category at commit time, and only when it still matches the displayed
    /// coordinates (the user may have tapped a different POI on the map since).
    @State private var lastPickedItem: ChooseLocationItem?

    private let smallDetent: PresentationDetent = .height(120)
    private let mediumDetent: PresentationDetent = .fraction(0.5)
    private let largeDetent: PresentationDetent = .large
    /// Detail sits lower than search — just tall enough for the summary, header,
    /// and Add-to-plan button.
    private let detailDetent: PresentationDetent = .fraction(0.4)

    private var detentSet: Set<PresentationDetent> {
        sheetContent == .search
            ? [mediumDetent, largeDetent]
            : [smallDetent, detailDetent]
    }

    private let topEntries: [LocationTopEntry] = [
        LocationTopEntry(
            id: "jason",
            name: "Jason Kim",
            mutualFriendsText: "0 mutual friends",
            ranking: "12x",
            isFriend: false
        ),
        LocationTopEntry(
            id: "hmy",
            name: "hmy",
            mutualFriendsText: "4 mutual friends",
            ranking: "8x",
            isFriend: true
        ),
        LocationTopEntry(
            id: "cattie",
            name: "Cattie",
            mutualFriendsText: "12 mutual friends",
            ranking: "8x",
            isFriend: true
        ),
        LocationTopEntry(
            id: "thanh_danh",
            name: "Thanh Danh",
            mutualFriendsText: "4 mutual friends",
            ranking: "7x",
            isFriend: true
        ),
        LocationTopEntry(
            id: "chan",
            name: "Chấn bé đù",
            mutualFriendsText: "3 mutual friends",
            ranking: "2x",
            isFriend: false
        ),
    ]

    private let mapCameraDistance: CLLocationDistance = 900
    private let mapCameraPitch3D: CGFloat = 58
    private let mapCameraPitch2D: CGFloat = 0
    private let mapCameraDistance2D: CLLocationDistance = 1200
    private let cameraOrbitStepDuration: TimeInterval = 0.12
    private let cameraOrbitHeadingIncrement: CLLocationDirection = 1
    private let sheetCornerRadius: CGFloat = 32
    private let sheetDownwardSnapThreshold: CGFloat = 90
    private let sheetUpwardSnapThreshold: CGFloat = 90
    private let topScrollTolerance: CGFloat = 8
    private let mediumSheetBottomMargin: CGFloat = 8
    private let minimumMediumSheetHeight: CGFloat = 240
    private let compassWidgetHeight: CGFloat = 60
    private let compassWidgetSheetGap: CGFloat = 8
    /// Beyond this, MapKit's camera fly takes many seconds (its real duration
    /// scales with distance, ignoring the SwiftUI animation hint) — snap instead.
    private let directionsFlyAnimationMaxMeters: CLLocationDistance = 30_000

    private var effectiveUserLocation: CLLocation? {
        userLocation ?? mapSearchService.userLocation
    }

    var body: some View {
        pickerBody
        .background(Constants.Background.ignoresSafeArea())
        .onChange(of: sheetMode) { _, newMode in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // Directions mode owns the camera; don't let sheet-mode side
            // effects (orbit, 2D/3D recenter on the destination) clobber the
            // midpoint framing that enterDirectionsMode set up.
            guard !isShowingDirections else { return }

            switch newMode {
            case .expanded:
                stopCameraOrbit()
                clearPOISelection()
                // Animate to 3D view
                withAnimation(.easeInOut(duration: 0.4)) {
                    mapCameraPosition = cameraPosition(
                        heading: currentMapHeading,
                        is2D: false
                    )
                }
            case .medium:
                // Animate to 3D view and start orbit
                withAnimation(.easeInOut(duration: 0.4)) {
                    mapCameraPosition = cameraPosition(
                        heading: currentMapHeading,
                        is2D: false
                    )
                }
                startCameraOrbit()
            case .minimized:
                stopCameraOrbit()
                // Animate to 2D view
                withAnimation(.easeInOut(duration: 0.4)) {
                    mapCameraPosition = cameraPosition(
                        heading: currentMapHeading,
                        is2D: true
                    )
                }
            }
        }
        // Picker-mode camera: native detents are discrete, so drive 2D/3D +
        // orbit off the settled detent (replaces the read-only drag tracking).
        .onChange(of: selectedDetent) { _, _ in
            handleDetentChange()
        }
        .onAppear { handleAppear() }
        .onChange(of: selectedMapFeature) { _, newFeature in
            guard let feature = newFeature else { return }
            handlePOISelection(feature)
        }
        .task(id: displayedName) {
            guard !displayedName.isEmpty else { return }
            do {
                let response = try await APIClient.shared.getLocationPlanCount(
                    query: .init(location: displayedName)
                )
                let result = try response.ok.body.json
                planAddCount = result.count
            } catch {
                planAddCount = nil
            }
        }
        .task {
            guard userLocation == nil else { return }
            await mapSearchService.configureWithUserLocation()
            // Picker entry centers the map on the user once their location is
            // resolved (the initial `.userLocation` camera may have fallen back
            // to automatic before authorization completed).
            if isPickerMode, sheetContent == .search,
                let coord = mapSearchService.userLocation?.coordinate
            {
                withAnimation(.easeInOut(duration: 0.4)) {
                    mapCameraPosition = .region(
                        MKCoordinateRegion(
                            center: coord,
                            latitudinalMeters: 1200,
                            longitudinalMeters: 1200
                        )
                    )
                }
            }
        }
        .onDisappear {
            stopCameraOrbit()
            deviceHeading.stop()
        }
    }

    // MARK: - Read-only body (custom draggable sheet)

    private var readOnlyBody: some View {
        GeometryReader { proxy in
            // Expanded - sheet near top (~15% from top)
            let expandedTopInset = max(
                proxy.safeAreaInsets.top + 100,
                proxy.size.height * 0.15
            )

            // Minimized - sheet at bottom (~70% from top, just peek)
            let minimizedTopInset = proxy.size.height * 0.83

            // Medium adapts to content height so the primary action stays visible.
            let mediumSheetHeight = max(
                sheetContentHeight + proxy.safeAreaInsets.bottom
                    + mediumSheetBottomMargin,
                minimumMediumSheetHeight
            )
            let mediumTopInset = min(
                max(
                    proxy.size.height - mediumSheetHeight,
                    expandedTopInset
                ),
                minimizedTopInset
            )

            let restingTopInset: CGFloat = {
                switch sheetMode {
                case .expanded: return expandedTopInset
                case .medium: return mediumTopInset
                case .minimized: return minimizedTopInset
                }
            }()

            // Clamp to medium (expanded disabled for now)
            let liveTopInset = min(
                max(restingTopInset + activeSheetDrag, mediumTopInset),
                minimizedTopInset
            )

            ZStack(alignment: .topLeading) {
                mapLayer
                    .onTapGesture {
                        switch sheetMode {
                        case .minimized:
                            if selectedPOICoordinate != nil {
                                clearPOISelection()
                            }
                        case .medium, .expanded:
                            transitionTo(.minimized)
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { _ in
                                if sheetMode == .minimized {
                                    // Close annotation when dragging in 2D
                                    if selectedPOICoordinate != nil {
                                        clearPOISelection()
                                    }
                                } else if sheetMode == .medium
                                    || sheetMode == .expanded
                                {
                                    // Transition to minimized/2D when dragging map in 3D
                                    transitionTo(.minimized)
                                }
                            }
                    )

                if !isShowingDirections {
                    backButton

                    detailSheet
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .top
                        )
                        .offset(y: liveTopInset)
                        .simultaneousGesture(
                            sheetDragGesture(
                                canStartDownwardDrag: isContentAtTop,
                                expandedTopInset: expandedTopInset,
                                mediumTopInset: mediumTopInset,
                                minimizedTopInset: minimizedTopInset,
                                restingTopInset: restingTopInset
                            )
                        )
                }

                if !isShowingDirections,
                    sheetMode != .expanded,
                    let distanceText,
                    let bearing = bearingFromUser
                {
                    LocationCompassWidget(
                        distanceText: distanceText,
                        bearingDegrees: bearing,
                        deviceHeadingDegrees: deviceHeading.trueHeading ?? 0,
                        onTap: { enterDirectionsMode() }
                    )
                    .frame(height: compassWidgetHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(
                        y: liveTopInset - compassWidgetHeight
                            - compassWidgetSheetGap
                    )
                    .zIndex(1)
                    .animation(.easeInOut(duration: 0.2), value: sheetMode)
                }

                if isShowingDirections {
                    directionsOverlays
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Picker body (native morphing sheet)

    private var pickerBody: some View {
        ZStack(alignment: .topLeading) {
            mapLayer
                .onTapGesture {
                    if isShowingDirections {
                        // Tapping the map exits directions back to the detail sheet.
                        exitDirectionsMode()
                    } else if selectedPOICoordinate != nil {
                        clearPOISelection()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in
                            if isShowingDirections {
                                // Dragging the map exits directions back to detail.
                                exitDirectionsMode()
                            } else if sheetContent == .detail, selectedDetent != smallDetent {
                                // Dragging the map minimizes the sheet to the peek
                                // detent (2D + interactive) so the user can pan around.
                                stopCameraOrbit()
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedDetent = smallDetent
                                }
                            } else {
                                // Already minimized / in search — just stop the orbit
                                // so periodic camera writes don't fight the pan.
                                stopCameraOrbit()
                            }
                        }
                )

            if !isShowingDirections {
                backButton
            }

            if sheetContent == .detail, !isShowingDirections,
                let distanceText,
                let bearing = bearingFromUser
            {
                GeometryReader { proxy in
                    LocationCompassWidget(
                        distanceText: distanceText,
                        bearingDegrees: bearing,
                        deviceHeadingDegrees: deviceHeading.trueHeading ?? 0,
                        onTap: { enterDirectionsMode() }
                    )
                    .frame(height: compassWidgetHeight)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
                    .padding(.bottom, compassBottomInset(for: selectedDetent, proxy: proxy))
                    .animation(.easeInOut(duration: 0.2), value: selectedDetent)
                }
                .zIndex(1)
            }

            if isShowingDirections {
                directionsOverlays
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isSheetPresented) {
            morphingSheet
        }
    }

    // MARK: - Shared overlays

    private var backButton: some View {
        ToolbarIconButton(systemName: "chevron.left") {
            handleBackButton()
        }
        .padding(.top, 8)
        .padding(.leading, 16)
        .zIndex(2)
    }

    private func handleBackButton() {
        // In picker detail, the map back chevron returns to search instead of
        // closing the whole picker.
        if isPickerMode, sheetContent == .detail, !isShowingDirections {
            returnToSearch()
        } else {
            onDismiss()
            dismiss()
        }
    }

    @ViewBuilder
    private var directionsOverlays: some View {
        VStack(spacing: 12) {
            Spacer()
            LocationDirectionsControlBar(
                selectedMode: directionsTransportMode,
                travelMinutes: estimatedTravelMinutes,
                onCollapse: { exitDirectionsMode() },
                onSelectMode: { mode in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        directionsTransportMode = mode
                    }
                },
                onOpenInAppleMaps: { openInAppleMaps() },
                onOpenInGoogleMaps: { openInGoogleMaps() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .bottom
        )
        .transition(
            .move(edge: .bottom).combined(with: .opacity)
        )
        .zIndex(2)
    }

    // MARK: - Morphing sheet (picker mode)

    @ViewBuilder
    private var morphingSheet: some View {
        NavigationStack {
            switch sheetContent {
            case .search:
                searchSheetContent
            case .detail:
                detailSheetContent
            }
        }
        .presentationDetents(detentSet, selection: $selectedDetent)
        .presentationBackgroundInteraction(
            .enabled(upThrough: sheetContent == .search ? mediumDetent : detailDetent)
        )
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        // Prioritize resizing the sheet on an upward swipe over scrolling the
        // inner Recently-viewed / Suggested lists.
        .presentationContentInteraction(.resizes)
    }

    private var searchSheetContent: some View {
        ChooseLocationPickerContent(
            tripId: pickerConfig?.tripId,
            dayNumber: pickerConfig?.dayNumber,
            planDate: pickerConfig?.planDate,
            onPlaceSelected: { item in flyToSelectedPlace(item) },
            onPinsAddedToTrip: {
                pickerConfig?.onPinsAddedToTrip()
                onDismiss()
                dismiss()
            },
            onBoardPinsSelected: pickerConfig?.onBoardPinsSelected,
            onClose: {
                onDismiss()
                dismiss()
            }
        )
    }

    @ViewBuilder
    private var detailSheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LocationDetailSummaryStrip(
                    distanceText: distanceText,
                    visitorsText: planCountText,
                    visitorsAvatarCount: 0
                )

                LocationDetailHeaderSection(
                    title: displayedName,
                    address: displayedAddress,
                    descriptionText: "This place not only attracts you with its unique flavors but also with the perfect blend of a casual dining atmosphere and the warmth of the people here."
                )

                if showsAddToPlan {
                    PrimaryButton(title: "\(addToPlanButtonTitle)") {
                        if isPickerMode {
                            commitPickedLocation()
                        } else {
                            // Read-only standalone usages (e.g. BoardDetailView)
                            // report through onAddToPlan.
                            onAddToPlan(
                                displayedName,
                                displayedAddress,
                                displayedLatitude,
                                displayedLongitude
                            )
                        }
                    }
                    .padding(.top, 22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func returnToSearch() {
        clearPOISelection()
        withAnimation(.easeInOut(duration: 0.25)) {
            sheetContent = .search
        }
        selectedDetent = mediumDetent
    }

    // MARK: - Picker mode helpers

    private func handleAppear() {
        deviceHeading.start()

        // Picker entry with no preset place: start in search centered on the user.
        if isPickerMode, initialLocationName.isEmpty {
            sheetContent = .search
            selectedDetent = mediumDetent
            isSheetPresented = true
            mapCameraPosition = .userLocation(fallback: .automatic)
            return
        }

        // Preset place (read-only standalone, or picker opened on a place).
        displayedName = initialLocationName
        displayedAddress = initialLocationAddress
        displayedLatitude = initialLatitude
        displayedLongitude = initialLongitude
        selectedPOICoordinate = CLLocationCoordinate2D(
            latitude: initialLatitude,
            longitude: initialLongitude
        )
        selectedPOIName = initialLocationName
        mapCameraPosition = cameraPosition(heading: 0, is2D: false)
        startCameraOrbit()

        // Open straight to the detail sheet (both picker-with-preset and the
        // read-only standalone usages).
        sheetContent = .detail
        selectedDetent = detailDetent
        isSheetPresented = true
    }

    /// Camera response to a settled detent change (picker mode). Native detents
    /// are discrete, so this replaces the read-only continuous drag tracking.
    private func handleDetentChange() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard !isShowingDirections else { return }

        // Search keeps a flat overview centered on the user — don't recenter on
        // the (possibly empty) displayed coordinate.
        guard sheetContent == .detail else {
            stopCameraOrbit()
            return
        }

        if selectedDetent == smallDetent {
            stopCameraOrbit()
            withAnimation(.easeInOut(duration: 0.4)) {
                mapCameraPosition = cameraPosition(heading: currentMapHeading, is2D: true)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                mapCameraPosition = cameraPosition(heading: currentMapHeading, is2D: false)
            }
            startCameraOrbit()
        }
    }

    /// A single place was picked in the search sheet: fly the map and morph to
    /// the detail surface.
    private func flyToSelectedPlace(_ item: ChooseLocationItem) {
        lastPickedItem = item
        displayedName = item.title
        displayedAddress = item.address
        displayedLatitude = item.latitude ?? 0
        displayedLongitude = item.longitude ?? 0
        selectedPOICoordinate = CLLocationCoordinate2D(
            latitude: displayedLatitude,
            longitude: displayedLongitude
        )
        selectedPOIName = item.title

        // The sheet morph stays animated (UI, not the camera).
        withAnimation(.easeInOut(duration: 0.25)) {
            sheetContent = .detail
        }
        // Set the selected detent AFTER the content/detentSet swap so the
        // selection binding doesn't race the system's settle.
        selectedDetent = detailDetent

        flyToDisplayedPlaceThenOrbit()
    }

    /// Fly the camera to the current displayed place, then begin the 3D orbit
    /// once the fly settles. Starting the orbit mid-fly re-targets the camera on
    /// every step and drags the transition into a slow creep, so it is delayed
    /// past MapKit's (longer-than-the-hint) camera move.
    private func flyToDisplayedPlaceThenOrbit(flyDuration: TimeInterval = 0.4) {
        stopCameraOrbit()
        withAnimation(.easeInOut(duration: flyDuration)) {
            mapCameraPosition = cameraPosition(heading: currentMapHeading, is2D: false)
        }
        cameraOrbitTask = Task {
            try? await Task.sleep(for: .seconds(flyDuration + 0.35))
            guard !Task.isCancelled else { return }
            startCameraOrbit()
        }
    }

    /// Commit the displayed place to the caller and close the host. Sources from
    /// the LIVE displayed state (the user may have tapped a different POI after
    /// picking); category is recovered from the picked item only when the
    /// coordinates still match.
    private func commitPickedLocation() {
        guard let config = pickerConfig else { return }
        let category: String? = {
            guard let picked = lastPickedItem,
                picked.latitude == displayedLatitude,
                picked.longitude == displayedLongitude
            else { return nil }
            return picked.category
        }()
        let item = ChooseLocationItem(
            id: UUID().uuidString,
            title: displayedName,
            address: displayedAddress,
            imageName: nil,
            latitude: displayedLatitude,
            longitude: displayedLongitude,
            category: category
        )
        config.onLocationSelected(item)
        onDismiss()
        dismiss()
    }

    private func compassBottomInset(for detent: PresentationDetent, proxy: GeometryProxy) -> CGFloat {
        if detent == smallDetent {
            return 120 + compassWidgetSheetGap
        }
        return proxy.size.height * 0.4 + compassWidgetSheetGap
    }

    private var distanceText: String? {
        guard let userLocation = effectiveUserLocation else { return nil }
        let destination = CLLocation(
            latitude: displayedLatitude,
            longitude: displayedLongitude
        )
        let meters = userLocation.distance(from: destination)
        // Locale-aware numbers (decimal/grouping separators); units stay m/km.
        if meters < 1000 {
            let rounded = Int((meters / 50).rounded() * 50)
            return "\(rounded.formatted())m"
        } else if meters < 10_000 {
            return "\((meters / 1000).formatted(.number.precision(.fractionLength(1))))km"
        } else {
            return "\(Int((meters / 1000).rounded()).formatted())km"
        }
    }

    private var bearingFromUser: Double? {
        guard let userLocation = effectiveUserLocation else { return nil }
        return Self.bearing(
            from: userLocation.coordinate,
            to: locationCoordinate
        )
    }

    private static func bearing(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let dLon = (destination.longitude - origin.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private var planCountText: String? {
        guard let planAddCount else { return nil }
        if planAddCount == 0 {
            return String(localized: "Be the first to add to plan")
        }
        return String(localized: "\(planAddCount.formatted())+ added to plan", comment: "%@ = formatted count")
    }

    private var isContentAtTop: Bool { 
        contentScrollOffset >= -topScrollTolerance
    }

    private var mapInteractionModes: MapInteractionModes {
        if isShowingDirections { return .all }
        if sheetContent == .search { return .all }
        // Detail: pannable only at the peek detent (3D orbit owns the rest).
        return selectedDetent == smallDetent ? .all : []
    }

    private var mapLayer: some View {
        Map(
            position: $mapCameraPosition,
            interactionModes: mapInteractionModes,
            selection: $selectedMapFeature
        ) {
            // Main location marker — suppressed in picker search mode, where no
            // place is chosen yet (otherwise a stray pin lands at 0,0).
            if !isShowingDirections, !(isPickerMode && sheetContent == .search) {
                Marker(displayedName, coordinate: locationCoordinate)
                    .tint(.blue)
            }

            // Always-on user-location dot with heading cone.
            if let user = effectiveUserLocation?.coordinate {
                Annotation("", coordinate: user, anchor: .center) {
                    ZStack {
                        UserHeadingCone()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.55),
                                        Color.blue.opacity(0.0),
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 60, height: 60)
                            .offset(y: -30)
                            .rotationEffect(
                                .degrees(
                                    (deviceHeading.trueHeading ?? 0)
                                        - currentMapHeading
                                )
                            )

                        Circle().fill(Color.white)
                            .frame(width: 22, height: 22)
                        Circle().fill(Color.blue)
                            .frame(width: 16, height: 16)
                    }
                }
                .annotationTitles(.hidden)
            }

            // Directions-mode overlays: callout for destination + curved arc.
            if isShowingDirections, let user = effectiveUserLocation?.coordinate {
                Annotation("", coordinate: locationCoordinate, anchor: .bottom) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image("appLogoCutout")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayedName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: 220, alignment: .leading)

                                Text("Recently Viewed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Constants.ContentB)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            .white,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .shadow(
                            color: .black.opacity(0.1),
                            radius: 8,
                            x: 0,
                            y: 2
                        )

                        Circle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                    }
                }
                .annotationTitles(.hidden)

                MapPolyline(
                    coordinates: Self.curvedRouteCoordinates(
                        from: user,
                        to: locationCoordinate
                    )
                )
                .stroke(
                    Color.blue,
                    style: StrokeStyle(
                        lineWidth: 1,
                        lineCap: .round,
                        dash: [8, 6]
                    )
                )
            }

            // Custom callout for selected POI
            if !isShowingDirections,
                let coord = selectedPOICoordinate,
                let name = selectedPOIName
            {
                Annotation("", coordinate: coord, anchor: .bottom) {
                    VStack(spacing: 0) {
                        // Callout bubble
                        HStack(spacing: 12) {
                            Image("appLogoCutout")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: 220, alignment: .leading)

                                Text("Recently Viewed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Constants.ContentB)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            .white,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .shadow(
                            color: .black.opacity(0.1),
                            radius: 8,
                            x: 0,
                            y: 2
                        )

                        // Pointer dot
                        Circle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            currentMapHeading = context.camera.heading
        }
        .mapFeatureSelectionAccessoryNoneCompat()
        .mapFeatureSelectionContent { feature in
            // Replace default POI marker with invisible annotation
            Annotation("", coordinate: feature.coordinate) {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .ignoresSafeArea()
    }

    private var detailSheet: some View {
        LocationDetailBottomSheet(
            cornerRadius: sheetCornerRadius,
            contentScrollOffset: $contentScrollOffset,
            contentHeight: $sheetContentHeight,
            scrollDisabled: (sheetMode == .expanded && activeSheetDrag > 0)
                || (sheetMode == .minimized && activeSheetDrag < 0)
                || sheetMode == .medium,
            floatingImage: {
                EmptyView()
            },
            content: {
                LocationDetailSummaryStrip(
                    distanceText: distanceText,
                    visitorsText: planCountText,
                    visitorsAvatarCount: 0
                )

                LocationDetailHeaderSection(
                    title: displayedName,
                    address: displayedAddress,
                    descriptionText: "This place not only attracts you with its unique flavors but also with the perfect blend of a casual dining atmosphere and the warmth of the people here."
                )

                if showsAddToPlan {
                    PrimaryButton(title: "\(addToPlanButtonTitle)") {
                        onAddToPlan(
                            displayedName,
                            displayedAddress,
                            displayedLatitude,
                            displayedLongitude
                        )
                    }
                    .padding(.top, 22)
                }

                //                LocationDetailTabBar(selectedTab: $selectedTab)
                //                LocationDetailTabContent(
                //                    selectedTab: selectedTab,
                //                    topEntries: topEntries
                //                )
            }
        )
    }

    private func sheetDragGesture(
        canStartDownwardDrag: Bool,
        expandedTopInset: CGFloat,
        mediumTopInset: CGFloat,
        minimizedTopInset: CGFloat,
        restingTopInset: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.height

                // Stop orbit during drag so camera interpolation is smooth
                stopCameraOrbit()

                switch sheetMode {
                case .expanded:
                    // Only allow downward drag when content at top
                    guard canStartDownwardDrag, translation > 0 else {
                        activeSheetDrag = 0
                        return
                    }
                    activeSheetDrag = translation
                case .medium:
                    // Allow both directions from medium
                    activeSheetDrag = translation
                case .minimized:
                    // Only allow upward drag
                    guard translation < 0 else {
                        activeSheetDrag = 0
                        return
                    }
                    activeSheetDrag = translation
                }

                // Continuous haptic feedback every 15pt of drag
                let hapticInterval: CGFloat = 15
                let currentPosition = restingTopInset + translation

                if abs(currentPosition - lastHapticDragPosition)
                    >= hapticInterval
                {
                    UISelectionFeedbackGenerator().selectionChanged()
                    lastHapticDragPosition = currentPosition
                }

                // Stronger haptic when crossing state boundary
                let distanceToMedium = abs(currentPosition - mediumTopInset)
                let distanceToMinimized = abs(
                    currentPosition - minimizedTopInset
                )
                let currentZone =
                    distanceToMedium <= distanceToMinimized ? 0 : 1

                if currentZone != lastDragHapticZone {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    lastDragHapticZone = currentZone
                }

                // Interpolate camera between 2D and 3D based on sheet position
                updateCameraForSheetPosition(
                    currentPosition: currentPosition,
                    mediumTopInset: mediumTopInset,
                    minimizedTopInset: minimizedTopInset
                )
            }
            .onEnded { value in
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let currentPosition = restingTopInset + translation

                // Distances to each state (expanded disabled for now)
                let distanceToMedium = abs(currentPosition - mediumTopInset)
                let distanceToMinimized = abs(
                    currentPosition - minimizedTopInset
                )

                // High velocity thresholds for skip-state transitions
                let highVelocityThreshold: CGFloat = 500
                let isHighVelocityUp = predicted < -highVelocityThreshold
                let isHighVelocityDown = predicted > highVelocityThreshold

                let targetState: LocationDetailSheetMode

                if isHighVelocityUp {
                    // Cap at medium (expanded disabled)
                    targetState = .medium
                } else if isHighVelocityDown {
                    targetState = .minimized
                } else {
                    // Snap to nearest state (only medium or minimized)
                    if distanceToMedium <= distanceToMinimized {
                        targetState = .medium
                    } else {
                        targetState = .minimized
                    }
                }

                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    sheetMode = targetState
                    activeSheetDrag = 0
                }

                // Reset haptic trackers
                lastDragHapticZone = targetState == .medium ? 0 : 1
                lastHapticDragPosition =
                    targetState == .medium ? mediumTopInset : minimizedTopInset
            }
    }

    private func transitionTo(_ mode: LocationDetailSheetMode) {
        guard sheetMode != mode else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            sheetMode = mode
        }
    }

    private func cameraPosition(
        heading: CLLocationDirection,
        is2D: Bool = false
    ) -> MapCameraPosition {
        .camera(
            MapCamera(
                centerCoordinate: locationCoordinate,
                distance: is2D ? mapCameraDistance2D : mapCameraDistance,
                heading: heading,
                pitch: is2D ? mapCameraPitch2D : mapCameraPitch3D
            )
        )
    }

    private func enterDirectionsMode() {
        guard effectiveUserLocation != nil, !isShowingDirections else { return }
        stopCameraOrbit()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.35)) {
            isShowingDirections = true
            isSheetPresented = false   // hide the detail sheet
        }
        if shouldAnimateDirectionsFly {
            withAnimation(.easeInOut(duration: 0.35)) {
                mapCameraPosition = directionsCameraPosition()
            }
        } else {
            // Far destination: MapKit would fly for many seconds — snap there.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mapCameraPosition = directionsCameraPosition()
            }
        }
    }

    private var shouldAnimateDirectionsFly: Bool {
        guard let meters = straightLineDistanceMeters else { return true }
        return meters <= directionsFlyAnimationMaxMeters
    }

    private func exitDirectionsMode() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopCameraOrbit()
        // Fly back to the place quickly. Keep the orbit OFF until the fly fully
        // settles — MapKit's camera move runs longer than the SwiftUI hint, so
        // starting the orbit too early re-targets mid-fly and drags it out.
        let flyDuration: TimeInterval = 0.4
        withAnimation(.easeInOut(duration: flyDuration)) {
            isShowingDirections = false
            isSheetPresented = true    // restore the detail sheet
        }
        if shouldAnimateDirectionsFly {
            withAnimation(.easeInOut(duration: flyDuration)) {
                mapCameraPosition = cameraPosition(heading: currentMapHeading, is2D: false)
            }
        } else {
            // Same far-destination snap as enterDirectionsMode — the return
            // fly from the zoomed-out midpoint is just as long.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mapCameraPosition = cameraPosition(heading: currentMapHeading, is2D: false)
            }
        }
        cameraOrbitTask = Task {
            try? await Task.sleep(for: .seconds(flyDuration + 0.35))
            guard !Task.isCancelled else { return }
            startCameraOrbit()
        }
    }

    private func directionsCameraPosition() -> MapCameraPosition {
        guard let user = effectiveUserLocation?.coordinate else {
            return mapCameraPosition
        }
        let midpoint = CLLocationCoordinate2D(
            latitude: (user.latitude + locationCoordinate.latitude) / 2,
            longitude: (user.longitude + locationCoordinate.longitude) / 2
        )
        let separationMeters = CLLocation(
            latitude: user.latitude,
            longitude: user.longitude
        ).distance(
            from: CLLocation(
                latitude: locationCoordinate.latitude,
                longitude: locationCoordinate.longitude
            )
        )
        // Distance scales with separation so farther destinations get a higher
        // camera. 5× covers MapKit's iPhone FOV (~30° vertical) after reserving
        // ~40% vertical room for top label + bottom card. 1500 m floor avoids
        // an overly tight zoom for very close points.
        let cameraDistance = max(separationMeters * 5.0, 1500)
        return .camera(
            MapCamera(
                centerCoordinate: midpoint,
                distance: cameraDistance,
                heading: 0,
                pitch: 0
            )
        )
    }

    /// Sample a slightly curved Bezier-like arc between two coordinates so the
    /// route line reads as an inviting curve rather than a stiff straight dash.
    private static func curvedRouteCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        sampleCount: Int = 48,
        curvature: Double = 0.18
    ) -> [CLLocationCoordinate2D] {
        let dLat = destination.latitude - origin.latitude
        let dLon = destination.longitude - origin.longitude
        // Perpendicular unit vector (in lat/lon space) for the control offset.
        let length = sqrt(dLat * dLat + dLon * dLon)
        guard length > 0 else { return [origin, destination] }
        let perpLat = -dLon / length
        let perpLon = dLat / length
        let midLat = (origin.latitude + destination.latitude) / 2
        let midLon = (origin.longitude + destination.longitude) / 2
        let controlLat = midLat + perpLat * length * curvature
        let controlLon = midLon + perpLon * length * curvature

        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(sampleCount + 1)
        for step in 0...sampleCount {
            let t = Double(step) / Double(sampleCount)
            let oneMinusT = 1 - t
            let lat = oneMinusT * oneMinusT * origin.latitude
                + 2 * oneMinusT * t * controlLat
                + t * t * destination.latitude
            let lon = oneMinusT * oneMinusT * origin.longitude
                + 2 * oneMinusT * t * controlLon
                + t * t * destination.longitude
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return coords
    }

    private var straightLineDistanceMeters: Double? {
        guard let userLocation = effectiveUserLocation else { return nil }
        let destination = CLLocation(
            latitude: displayedLatitude,
            longitude: displayedLongitude
        )
        return userLocation.distance(from: destination)
    }

    private var estimatedTravelMinutes: Int {
        guard let meters = straightLineDistanceMeters else { return 0 }
        let minutes = meters / directionsTransportMode.paceMetersPerMinute
        return max(1, Int(minutes.rounded()))
    }

    private func openInAppleMaps() {
        let placemark = MKPlacemark(coordinate: locationCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = displayedName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: directionsTransportMode
                .mapsLaunchMode
        ])
    }

    private func openInGoogleMaps() {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(displayedLatitude),\(displayedLongitude)"),
            URLQueryItem(name: "travelmode", value: directionsTransportMode.googleMapsTravelMode),
        ]

        guard let url = components?.url else { return }
        openURL(url)
    }

    /// Interpolate camera between 2D (minimized) and 3D (medium) based on sheet position
    private func updateCameraForSheetPosition(
        currentPosition: CGFloat,
        mediumTopInset: CGFloat,
        minimizedTopInset: CGFloat
    ) {
        // Progress: 0 = minimized (2D), 1 = medium (3D)
        let progress = min(
            max(
                (minimizedTopInset - currentPosition)
                    / (minimizedTopInset - mediumTopInset),
                0
            ),
            1
        )

        let interpolatedPitch =
            mapCameraPitch2D + progress * (mapCameraPitch3D - mapCameraPitch2D)
        let interpolatedDistance =
            mapCameraDistance2D - progress
            * (mapCameraDistance2D - mapCameraDistance)

        mapCameraPosition = .camera(
            MapCamera(
                centerCoordinate: locationCoordinate,
                distance: interpolatedDistance,
                heading: currentMapHeading,
                pitch: interpolatedPitch
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
                    withAnimation(.linear(duration: cameraOrbitStepDuration)) {
                        currentMapHeading = nextHeading
                        // Use 3D camera for medium state orbit
                        mapCameraPosition = cameraPosition(
                            heading: nextHeading,
                            is2D: false
                        )
                    }
                }

                try? await Task.sleep(
                    nanoseconds: UInt64(cameraOrbitStepDuration * 1_000_000_000)
                )
            }
        }
    }

    private func stopCameraOrbit() {
        cameraOrbitTask?.cancel()
        cameraOrbitTask = nil
    }

    private func handlePOISelection(_ feature: MapFeature) {
        let coordinate = feature.coordinate
        let poiName = feature.title ?? "Selected Location"

        // Haptic feedback for selection
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Stop orbit so camera stays on selected POI
        stopCameraOrbit()

        // Selecting a new POI exits directions mode so the bottom sheet returns.
        if isShowingDirections {
            withAnimation(.easeInOut(duration: 0.3)) {
                isShowingDirections = false
            }
        }

        // A fresh POI tap becomes the new selected place — morph the sheet to
        // detail. Clear lastPickedItem so the commit category falls back to nil
        // (the POI tap carries no category) unless re-picked.
        lastPickedItem = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            sheetContent = .detail
        }
        selectedDetent = detailDetent

        // Show custom callout immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedPOICoordinate = coordinate
            selectedPOIName = poiName
        }

        // Update displayed name immediately with POI name
        displayedName = poiName
        displayedLatitude = coordinate.latitude
        displayedLongitude = coordinate.longitude

        // Same fly-then-orbit as the search-pick path.
        flyToDisplayedPlaceThenOrbit()

        // Fetch detailed place info using local search
        Task {
            // Search for the POI by name at its location
            let searchRequest = MKLocalSearch.Request()
            searchRequest.naturalLanguageQuery = poiName
            searchRequest.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 100,
                longitudinalMeters: 100
            )

            let search = MKLocalSearch(request: searchRequest)
            do {
                let response = try await search.start()
                if let mapItem = response.mapItems.first {
                    await MainActor.run {
                        // Use full address from MKMapItem if available (iOS 26+),
                        // otherwise fall back to placemark components below.
                        if #available(iOS 26.0, *), let fullAddress = mapItem.address?.fullAddress {
                            displayedAddress = fullAddress
                        } else {
                            // Fallback to placemark components
                            let placemark = mapItem.placemark
                            displayedAddress = [
                                placemark.subThoroughfare,
                                placemark.thoroughfare,
                                placemark.locality,
                                placemark.administrativeArea,
                            ]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                        }
                    }
                }
            } catch {
                // Fallback to reverse geocoding
                let geocoder = CLGeocoder()
                let location = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    if let placemark = placemarks.first {
                        await MainActor.run {
                            displayedAddress = [
                                placemark.subThoroughfare,
                                placemark.thoroughfare,
                                placemark.locality,
                                placemark.administrativeArea,
                            ]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                        }
                    }
                } catch {
                    await MainActor.run {
                        displayedAddress = ""
                    }
                }
            }
        }
    }

    private func clearPOISelection() {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedPOICoordinate = nil
            selectedPOIName = nil
            selectedMapFeature = nil
        }
    }
}

private struct UserHeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let center = CGPoint(x: rect.midX, y: rect.maxY)
            let radius = rect.height
            let halfAngle: CGFloat = .pi / 6   // 30° → 60° total field
            let start = -.pi / 2 - halfAngle
            let end = -.pi / 2 + halfAngle
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(start),
                endAngle: .radians(end),
                clockwise: false
            )
            path.closeSubpath()
        }
    }
}

private extension View {
    /// Suppresses the default map feature-selection accessory on iOS 18+; no-op on iOS 17.
    /// `mapFeatureSelectionAccessory(_:)` is iOS 18.0+, so it must be availability-gated.
    @ViewBuilder
    func mapFeatureSelectionAccessoryNoneCompat() -> some View {
        if #available(iOS 18.0, *) {
            mapFeatureSelectionAccessory(.none)
        } else {
            self
        }
    }
}

#Preview {
    LocationDetailView(
        initialLocationName: "Hotpot",
        initialLocationAddress: "251 Nguyen Van Troi, P12, Da Lat City",
        initialLatitude: 11.9404,
        initialLongitude: 108.4583
    )
    .background(Constants.Background.ignoresSafeArea())
}
