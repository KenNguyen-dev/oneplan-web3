//
//  TripPlanSection.swift
//  OnePlan
//
//  Created by Codex on 26/2/26.
//

import CoreLocation
import MapKit
import SwiftUI

private struct TripPlanEntry {
    let title: String
    let location: String
    let markerColor: Color
    let description: String?
    let voiceDuration: String?
    let isVoiceGray: Bool
    let planItem: PlanItemDto
}

private struct TimedTripPlanEntry {
    let hour: Int
    let minute: Int
    let entry: TripPlanEntry

    var totalMinutes: Int {
        hour * 60 + minute
    }
}

private struct TripPlanRenderedEntry: Identifiable {
    let id: Int
    let timeLabel: String?
    let entry: TripPlanEntry
    let distanceToNext: String?
    let routeToNext: TripPlanRoute?
    let isLast: Bool
}

private struct TripPlanRoute {
    let id: String
    let sourceName: String
    let sourceCoordinate: CLLocationCoordinate2D
    let destinationName: String
    let destinationCoordinate: CLLocationCoordinate2D
}

enum TripPlanRearrangeMode {
    case days
    case dates
}

struct TripPlanSection: View {
    let allPlanItems: [PlanItemDto]
    let availableDayNumbers: [Int]
    let isLoading: Bool
    let isPlanningMode: Bool
    let dateForDay: (Int) -> Date?
    let dateStringForDay: (Int) -> String?
    let onAddPlanTapped: ((String) -> Void)?
    let onPlanTapped: ((PlanItemDto) -> Void)?
    let onAddPlanTappedDay: ((Int) -> Void)?
    let onShowRearrangeSheet: ((TripPlanRearrangeMode) -> Void)?
    let canAddDay: Bool
    let onAddDayTapped: (() -> Void)?
    let onViewDayMapTapped: ((String, [PlanDayPin], [PlanDayRouteLeg]) -> Void)?
    let tripId: Int?
    /// Read-only mode (offline) hides every write affordance (New Plan, add
    /// day, rearrange). Viewing the itinerary stays available.
    let isReadOnly: Bool

    @State private var selectedDayNumber: Int = 1
    @State private var hasSelectedInitialDay = false
    @State private var isShowingMarketSheet = false
    @State private var isShowingSubscriptionSheet = false
    @State private var marketSheetFeedService = MarketplaceFeedService()
    @State private var selectedMapRoute: TripPlanRoute?
    @State private var previewRouteLegs: [PlanDayRouteLeg] = []
    @Environment(StoreManager.self) private var storeManager

    init(
        tripId: Int? = nil,
        allPlanItems: [PlanItemDto] = [],
        availableDayNumbers: [Int] = [1],
        isLoading: Bool = false,
        isPlanningMode: Bool = false,
        dateForDay: @escaping (Int) -> Date? = { _ in nil },
        dateStringForDay: @escaping (Int) -> String? = { _ in nil },
        onAddPlanTapped: ((String) -> Void)? = nil,
        onPlanTapped: ((PlanItemDto) -> Void)? = nil,
        onAddPlanTappedDay: ((Int) -> Void)? = nil,
        onShowRearrangeSheet: ((TripPlanRearrangeMode) -> Void)? = nil,
        canAddDay: Bool = false,
        onAddDayTapped: (() -> Void)? = nil,
        onViewDayMapTapped: ((String, [PlanDayPin], [PlanDayRouteLeg]) -> Void)? = nil,
        isReadOnly: Bool = false
    ) {
        self.tripId = tripId
        self.isReadOnly = isReadOnly
        self.allPlanItems = allPlanItems
        self.availableDayNumbers = availableDayNumbers
        self.isLoading = isLoading
        self.isPlanningMode = isPlanningMode
        self.dateForDay = dateForDay
        self.dateStringForDay = dateStringForDay
        self.onAddPlanTapped = onAddPlanTapped
        self.onPlanTapped = onPlanTapped
        self.onAddPlanTappedDay = onAddPlanTappedDay
        self.onShowRearrangeSheet = onShowRearrangeSheet
        self.canAddDay = canAddDay
        self.onAddDayTapped = onAddDayTapped
        self.onViewDayMapTapped = onViewDayMapTapped
    }

    private func handleExploreOnMarketTap() {
        if storeManager.isPro {
            isShowingMarketSheet = true
        } else {
            isShowingSubscriptionSheet = true
        }
    }

    private func selectInitialDay() {
        guard !hasSelectedInitialDay else { return }
        if !isPlanningMode,
           let firstDay = availableDayNumbers.first,
           let lastDay = availableDayNumbers.last,
           let startDate = dateForDay(firstDay)
        {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let start = calendar.startOfDay(for: startDate)
            if let offset = calendar.dateComponents([.day], from: start, to: today).day {
                let candidate = firstDay + offset
                selectedDayNumber = max(firstDay, min(candidate, lastDay))
            } else {
                selectedDayNumber = firstDay
            }
        } else if let firstDay = availableDayNumbers.first {
            selectedDayNumber = firstDay
        }
        hasSelectedInitialDay = true
    }

    // MARK: - Timeline

    private var visiblePlanItems: [PlanItemDto] {
        if isPlanningMode {
            return allPlanItems.filter { Int($0.dayNumber ?? 0) == selectedDayNumber }
        }
        guard let dateString = dateStringForDay(selectedDayNumber) else {
            return []
        }
        return allPlanItems.filter { $0.planDate == dateString }
    }

    private var sortedTimedEntries: [TimedTripPlanEntry] {
        let timedEntries: [TimedTripPlanEntry] = visiblePlanItems.compactMap { item in
            guard let (hour, minute) = parseHourMinute(item.startTime) else { return nil }
            let entry = TripPlanEntry(
                title: item.title,
                location: item.location ?? "",
                markerColor: item.category.flatMap { CategoryChip.Category(apiValue: $0.value1.rawValue)?.selectedBackgroundColor } ?? Constants.Warning500,
                description: item.description,
                voiceDuration: item.voiceDuration.map { durationSeconds in
                    let totalSeconds = Int(durationSeconds)
                    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
                },
                isVoiceGray: false,
                planItem: item
            )
            return TimedTripPlanEntry(hour: hour, minute: minute, entry: entry)
        }

        return timedEntries.sorted { lhs, rhs in
            if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
            if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
            if lhs.entry.planItem.sortOrder != rhs.entry.planItem.sortOrder {
                return lhs.entry.planItem.sortOrder < rhs.entry.planItem.sortOrder
            }
            return lhs.entry.planItem.id < rhs.entry.planItem.id
        }
    }

    /// Day items in display order: timed entries first (time/sortOrder/id),
    /// then untimed items (sortOrder/id) so they still count as map pins.
    private var orderedDayItems: [PlanItemDto] {
        let timed = sortedTimedEntries.map { $0.entry.planItem }
        let untimed = visiblePlanItems
            .filter { parseHourMinute($0.startTime) == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.id < rhs.id
            }
        return timed + untimed
    }

    private var dayMapPins: [PlanDayPin] {
        orderedDayItems
            .compactMap { item -> (PlanItemDto, CLLocationCoordinate2D)? in
                guard let latitude = item.latitude, let longitude = item.longitude else {
                    return nil
                }
                return (item, CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            .enumerated()
            .map { offset, located in
                PlanDayPin(
                    id: Int(located.0.id),
                    index: offset + 1,
                    title: located.0.title,
                    coordinate: located.1,
                    subtitle: located.0.location,
                    timeLabel: parseHourMinute(located.0.startTime).map {
                        String(format: "%02d:%02d", $0.0, $0.1)
                    }
                )
            }
    }

    private var renderedTimeline: [TripPlanRenderedEntry] {
        let entries = sortedTimedEntries
        return entries.enumerated().map { index, timedEntry in
            let previousMinutes = index > 0 ? entries[index - 1].totalMinutes : nil
            let nextEntry = index < entries.index(before: entries.endIndex) ? entries[index + 1].entry : nil
            let shouldShowTime = previousMinutes != timedEntry.totalMinutes

            return TripPlanRenderedEntry(
                id: Int(timedEntry.entry.planItem.id),
                timeLabel: shouldShowTime ? String(format: "%02d:%02d", timedEntry.hour, timedEntry.minute) : nil,
                entry: timedEntry.entry,
                distanceToNext: nextEntry.flatMap {
                    distanceText(from: timedEntry.entry.planItem, to: $0.planItem)
                },
                routeToNext: nextEntry.flatMap {
                    route(from: timedEntry.entry, to: $0)
                },
                isLast: nextEntry == nil
            )
        }
    }

    private func distanceText(from current: PlanItemDto, to next: PlanItemDto) -> String? {
        guard let currentLatitude = current.latitude,
              let currentLongitude = current.longitude,
              let nextLatitude = next.latitude,
              let nextLongitude = next.longitude else {
            return nil
        }

        let currentLocation = CLLocation(latitude: currentLatitude, longitude: currentLongitude)
        let nextLocation = CLLocation(latitude: nextLatitude, longitude: nextLongitude)
        let kilometers = currentLocation.distance(from: nextLocation) / 1_000

        // Locale-aware number (decimal/grouping separators); unit stays km.
        if kilometers < 10 {
            return "\(kilometers.formatted(.number.precision(.fractionLength(1)))) km"
        }
        return "\(Int(kilometers.rounded()).formatted()) km"
    }

    private func route(from current: TripPlanEntry, to next: TripPlanEntry) -> TripPlanRoute? {
        guard let currentLatitude = current.planItem.latitude,
              let currentLongitude = current.planItem.longitude,
              let nextLatitude = next.planItem.latitude,
              let nextLongitude = next.planItem.longitude else {
            return nil
        }

        return TripPlanRoute(
            id: "\(current.planItem.id)-\(next.planItem.id)",
            sourceName: mapItemName(for: current),
            sourceCoordinate: CLLocationCoordinate2D(
                latitude: currentLatitude,
                longitude: currentLongitude
            ),
            destinationName: mapItemName(for: next),
            destinationCoordinate: CLLocationCoordinate2D(
                latitude: nextLatitude,
                longitude: nextLongitude
            )
        )
    }

    private func mapItemName(for entry: TripPlanEntry) -> String {
        let location = entry.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? entry.title : location
    }

    private func openRouteInAppleMaps(_ route: TripPlanRoute) {
        let sourcePlacemark = MKPlacemark(coordinate: route.sourceCoordinate)
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = route.sourceName

        let destinationPlacemark = MKPlacemark(coordinate: route.destinationCoordinate)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = route.destinationName

        MKMapItem.openMaps(
            with: [sourceItem, destinationItem],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }

    private func openRouteInGoogleMaps(_ route: TripPlanRoute) {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(
                name: "origin",
                value: "\(route.sourceCoordinate.latitude),\(route.sourceCoordinate.longitude)"
            ),
            URLQueryItem(
                name: "destination",
                value: "\(route.destinationCoordinate.latitude),\(route.destinationCoordinate.longitude)"
            ),
            URLQueryItem(name: "travelmode", value: "driving"),
        ]

        guard let url = components?.url else { return }
        // Uses UIApplication.shared.open instead of @Environment(\.openURL) ON
        // PURPOSE. Below iOS 26, the openURL/dismiss action env values get a fresh
        // identity on every NavigationStack relayout. With this view mounted in a
        // pushed stack (TripDetailView → plan tab) while a plan destination is
        // pushed, reading openURL here joined TripDetailView's/PlanDetailView's
        // \.dismiss reads to form a self-sustaining re-render loop that hung the
        // main thread (tapping New Plan / a plan item froze the app). Reading the
        // action env value is the loop's extra ingredient — dropping it breaks it.
        UIApplication.shared.open(url)
    }

    private func isMapSelectionPresented(for route: TripPlanRoute) -> Binding<Bool> {
        Binding(
            get: { selectedMapRoute?.id == route.id },
            set: { isPresented in
                if !isPresented {
                    selectedMapRoute = nil
                }
            }
        )
    }

    private func dismissMapSelection() {
        selectedMapRoute = nil
    }

    private func parseHourMinute(_ startTime: String?) -> (Int, Int)? {
        guard let startTime else { return nil }
        let trimmed = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return (hour, minute)
    }

    private var shouldShowEmptyState: Bool {
        renderedTimeline.isEmpty
    }

    private func triggerNewPlan() {
        if isPlanningMode {
            onAddPlanTappedDay?(selectedDayNumber)
        } else if let dateString = dateStringForDay(selectedDayNumber) {
            onAddPlanTapped?(dateString)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !availableDayNumbers.isEmpty {
                dayDateChipsView
            }

            if !isLoading, dayMapPins.count >= 2 {
                planOverviewCard
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if shouldShowEmptyState {
                VStack(spacing: 12) {
                    TripPlanEmpty()

                    if !isReadOnly {
                        if allPlanItems.isEmpty {
                            HStack(spacing: 8) {
                                SecondaryButton(title: "Explore on market", variant: .dark) {
                                    handleExploreOnMarketTap()
                                }

                                PrimaryButton(title: "New Plan") {
                                    triggerNewPlan()
                                }
                            }
                        } else {
                            PrimaryButton(title: "New Plan") {
                                triggerNewPlan()
                            }
                            .padding(.top, 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 0) {
                    SwiftUI.ForEach(renderedTimeline) { item in
                        HStack(alignment: .top, spacing: 10) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(item.timeLabel ?? "")
                                    .font(Font.custom("Be Vietnam Pro", size: 14))
                                    .foregroundColor(Constants.ContentM)
                                    .frame(width: 44, alignment: .leading)

                                Rectangle()
                                    .fill(Constants.ContentL.opacity(0.55))
                                    .frame(width: 24, height: 1)
                            }
                            .padding(.top, 6)

                            VStack(spacing: 0) {
                                Button {
                                    onPlanTapped?(item.entry.planItem)
                                } label: {
                                    PlanItem(
                                        title: item.entry.title,
                                        location: item.entry.location,
                                        markerColor: item.entry.markerColor,
                                        description: item.entry.description,
                                        voiceDuration: item.entry.voiceDuration,
                                        isVoiceGray: item.entry.isVoiceGray
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if let distanceToNext = item.distanceToNext,
                                   let routeToNext = item.routeToNext {
                                    Button {
                                        selectedMapRoute = routeToNext
                                    } label: {
                                        TripPlanDistanceConnector(distanceText: distanceToNext)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(
                                        isPresented: isMapSelectionPresented(for: routeToNext),
                                        attachmentAnchor: .rect(.bounds),
                                        arrowEdge: .top
                                    ) {
                                        VStack(alignment: .leading, spacing: 18) {
                                            Button {
                                                openRouteInAppleMaps(routeToNext)
                                                dismissMapSelection()
                                            } label: {
                                                Label("Apple Maps", systemImage: "map")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                openRouteInGoogleMaps(routeToNext)
                                                dismissMapSelection()
                                            } label: {
                                                Label("Google Maps", systemImage: "globe")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .font(Font.custom("Be Vietnam Pro", size: 15))
                                        .foregroundColor(Constants.ContentB)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 18)
                                        .frame(width: 240, alignment: .leading)
                                        .presentationCompactAdaptation(.popover)
                                    }
                                } else if !item.isLast {
                                    Color.clear.frame(height: 10)
                                }
                            }
                        }
                    }

                    if !isReadOnly {
                        PrimaryButton(title: "New Plan") {
                            triggerNewPlan()
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            selectInitialDay()
        }
        .onChange(of: isPlanningMode) { oldValue, newValue in
            if oldValue == true && newValue == false {
                hasSelectedInitialDay = false
                selectInitialDay()
            }
        }
        .onChange(of: availableDayNumbers) { _, newValue in
            guard !newValue.isEmpty else { return }
            if !newValue.contains(selectedDayNumber) {
                selectedDayNumber = newValue.last ?? 1
            }
        }
        .fullScreenCover(isPresented: $isShowingSubscriptionSheet) {
            SubscriptionView()
        }
        .fullScreenCover(isPresented: $isShowingMarketSheet) {
            NavigationStack {
                MarketView(marketplaceFeedService: marketSheetFeedService, tripId: tripId)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isShowingMarketSheet = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Constants.ContentB)
                            }
                            .buttonStyle(.plain)
                        }
                    }
            }
            .environment(marketSheetFeedService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketplacePlanApplied)) { _ in
            isShowingMarketSheet = false
        }
    }

    // MARK: - Plan Overview Card

    private var planOverviewCard: some View {
        Button {
            onViewDayMapTapped?(
                String(localized: "Day \(selectedDayNumber)"),
                dayMapPins,
                previewRouteLegs
            )
        } label: {
            VStack(spacing: 8) {
                overviewHeaderRow
                overviewMapPreview
            }
            .padding(8)
            .background(Constants.Surface)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var overviewHeaderRow: some View {
        HStack(spacing: 10) {
            Image("signpost")
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Plan overview")
                    .font(Font.beVietnamPro(16, weight: .medium))
                    .foregroundColor(Constants.ContentB)
                Text("\(dayMapPins.count) pins")
                    .font(Font.beVietnamPro(14))
                    .foregroundColor(Constants.ContentM)
            }

            Spacer(minLength: 8)

            Text("View details")
                .font(Font.beVietnamPro(15, weight: .medium))
                .foregroundColor(Constants.White)
                .padding(.horizontal, 20)
                .frame(height: 42)
                .background(Constants.BlueBase)
                .clipShape(Capsule())
        }
    }

    private var overviewMapPreview: some View {
        Map(
            position: .constant(.region(PlanDayPin.fittedRegion(for: dayMapPins))),
            interactionModes: []
        ) {
            // No straight-line placeholder: the route appears only once the
            // driving legs are loaded, so it never visibly re-shapes.
            ForEach(Array(previewRouteLegs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(leg.polyline)
                    .stroke(
                        Constants.BlueBase,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(dayMapPins) { pin in
                Annotation("", coordinate: pin.coordinate, anchor: .center) {
                    PlanDayNumberMarker(index: pin.index)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .task(id: dayMapPins.map(\.id)) {
            previewRouteLegs = []
            previewRouteLegs = await PlanDayPin.drivingRouteLegs(for: dayMapPins)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 219)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Unified Day/Date Chip Strip

    private var dayDateChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableDayNumbers, id: \.self) { day in
                    chip(for: day)
                        .onTapGesture {
                            selectedDayNumber = day
                        }
                        .onLongPressGesture(minimumDuration: 0.45) {
                            guard !isReadOnly else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onShowRearrangeSheet?(.days)
                        }
                }

                if canAddDay, !isReadOnly, let onAddDayTapped {
                    Button {
                        triggerAddDay(onAddDayTapped)
                    } label: {
                        Text("+ add")
                            .font(Font.beVietnamPro(15, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Constants.Surface)
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func triggerAddDay(_ callback: () -> Void) {
        callback()
        // Park selection one past the previous last day; the onChange clamp
        // below snaps it onto the newly-added day once the parent re-renders.
        selectedDayNumber = (availableDayNumbers.last ?? 0) + 1
    }

    @ViewBuilder
    private func chip(for day: Int) -> some View {
        let isSelected = selectedDayNumber == day
        if let date = dateForDay(day) {
            HStack(spacing: 6) {
                Text(DisplayFormatters.monthDay(date))
                    .font(Font.beVietnamPro(15, weight: .medium))
                    .foregroundColor(
                        isSelected ? Constants.White.opacity(0.7) : Constants.ContentM
                    )
                Text("Day \(day)")
                    .font(Font.beVietnamPro(17, weight: .semibold))
                    .foregroundColor(isSelected ? Constants.White : Constants.ContentB)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(isSelected ? Constants.BlueBase : Constants.Surface)
            .cornerRadius(20)
            .shadow(color: .black.opacity(isSelected ? 0 : 0.06), radius: 5, x: 0, y: 1)
        } else {
            Text("Day \(day)")
                .font(Font.beVietnamPro(17, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Constants.White : Constants.ContentB)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(isSelected ? Constants.BlueBase : Constants.Surface)
                .cornerRadius(20)
                .shadow(color: .black.opacity(isSelected ? 0 : 0.06), radius: 5, x: 0, y: 1)
        }
    }

}

private struct TripPlanDistanceConnector: View {
    let distanceText: String

    var body: some View {
        VStack(spacing: 2) {
            connectorLine

            HStack(spacing: 5) {
                Text(distanceText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Constants.White)

                Image("distanceArrow")
                    .resizable()
                    .frame(width: 12.027, height: 12)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Constants.BlueBase)
            .clipShape(Capsule())

            connectorLine
        }
        .frame(maxWidth: .infinity)
        .frame(height: 37)
    }

    private var connectorLine: some View {
        Rectangle()
            .fill(Constants.ContentL.opacity(0.22))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

#Preview {
    let sampleItems: [PlanItemDto] = [
        .init(
            id: 1,
            tripId: 1,
            planDate: nil,
            title: "Midnight Check-in",
            description: "Drop luggage and confirm room keys",
            location: "Hotel Lobby",
            latitude: 11.9404,
            longitude: 108.4583,
            startTime: "00:05",
            category: nil,
            voiceUrl: nil,
            voiceDuration: 32,
            dayNumber: 2,
            sortOrder: 0,
            createdAt: "2026-03-23T00:00:00Z",
            members: []
        ),
        .init(
            id: 2,
            tripId: 1,
            planDate: nil,
            title: "Morning Coffee",
            description: "Grab coffee at the local cafe",
            location: "The Coffee House",
            latitude: 11.9466,
            longitude: 108.4419,
            startTime: "08:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            dayNumber: 2,
            sortOrder: 1,
            createdAt: "2026-03-23T00:00:00Z",
            members: []
        ),
        .init(
            id: 3,
            tripId: 1,
            planDate: nil,
            title: "No Coordinate Stop",
            description: "This one should not show a distance connector before it",
            location: "Somewhere nearby",
            startTime: "09:30",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            dayNumber: 2,
            sortOrder: 2,
            createdAt: "2026-03-23T00:00:00Z",
            members: []
        ),
    ]

    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    let baseDate = formatter.date(from: "2026-05-25") ?? Date()
    return TripPlanSection(
        allPlanItems: sampleItems,
        availableDayNumbers: [1, 2, 3],
        isPlanningMode: true,
        dateForDay: { day in
            Calendar.current.date(byAdding: .day, value: day - 1, to: baseDate)
        },
        dateStringForDay: { day in
            guard let d = Calendar.current.date(byAdding: .day, value: day - 1, to: baseDate) else { return nil }
            return formatter.string(from: d)
        },
        canAddDay: true,
        onAddDayTapped: { print("add day tapped") }
    )
    .padding()
    .background(Constants.Background)
    .environment(StoreManager())
}
