//
//  ChooseLocationView.swift
//  OnePlan
//
//  Created by Codex on 8/3/26.
//

import MapKit
import SwiftUI

struct ChooseLocationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let address: String
    let imageName: String?
    var latitude: Double?
    var longitude: Double?
    var category: String?

    static func illustrationName(for poiCategory: MKPointOfInterestCategory?) -> String? {
        guard let poi = poiCategory else { return nil }
        // `.spa` is an iOS 18+ point-of-interest category; gate it so the switch
        // below stays valid on the iOS 17.2 deployment floor.
        if #available(iOS 18.0, *), poi == .spa {
            return "spa"
        }
        switch poi {
        case .hotel:
            return "hotel"
        case .foodMarket:
            return "grocery"
        case .fitnessCenter:
            return "gym"
        case .hospital, .pharmacy:
            return "medical"
        case .park, .nationalPark:
            return "park"
        case .airport:
            return "airport"
        case .cafe, .bakery:
            return "coffee"
        case .nightlife:
            return "night-club"
        case .store:
            return "shopping"
        case .restaurant:
            return "restaurant"
        case .movieTheater:
            return "cinema"
        case .museum:
            return "museum"
        default:
            return nil
        }
    }
}

/// The search + "My Board" picker UI, stripped of host chrome so it can be
/// embedded as the `search` surface of `LocationDetailView`'s native morphing
/// sheet. Reports the chosen place via `onPlaceSelected` (the host flies the
/// map + morphs to detail); bulk board adds flow through `onPinsAddedToTrip` /
/// `onBoardPinsSelected`. The host wraps this in a `NavigationStack` so the
/// board drill-in (`ChooseLocationBoardPinsView`) can push.
struct ChooseLocationPickerContent: View {
    private enum LocationTab: String, CaseIterable, Identifiable {
        case newPlace = "New place"
        case myBoard = "My Board"

        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .newPlace: String(localized: "New place", comment: "Location source tab")
            case .myBoard: String(localized: "My Board", comment: "Location source tab")
            }
        }
    }

    var tripId: Int? = nil
    /// Day-number to attach bulk-created plan items to (planning-mode trips).
    /// Mutually exclusive with `planDate`.
    var dayNumber: Int? = nil
    /// Plan-date (yyyy-MM-dd) to attach bulk-created plan items to (ongoing trips).
    /// Mutually exclusive with `dayNumber`.
    var planDate: String? = nil
    /// Called when the user picks a single place. The host warms up the map,
    /// flies to it, and morphs the sheet to the detail surface.
    var onPlaceSelected: (ChooseLocationItem) -> Void = { _ in }
    var onPinsAddedToTrip: () -> Void = {}
    /// When set, selecting board pins returns them to the caller (e.g. to append
    /// to an in-memory draft) instead of writing them to a trip via the API.
    /// Its presence also reveals the "My Board" tab even when `tripId` is nil.
    var onBoardPinsSelected: (([BoardPinDto]) -> Void)? = nil
    /// Cancel affordance — dismisses the whole host picker.
    var onClose: () -> Void = {}

    @Environment(UserProfileService.self) private var userProfileService

    @State private var selectedTab: LocationTab = .newPlace
    @State private var searchText = ""
    @State private var mapSearchService = MapSearchService()
    @State private var recentLocationService = RecentLocationService()
    @State private var boardService = BoardService.shared
    @State private var tripDetailService = TripDetailService()
    @State private var isPreparingMap = false
    @State private var isInitialLoading = true

    private var showsBoardTab: Bool {
        tripId != nil || onBoardPinsSelected != nil
    }

    private var visibleTabs: [LocationTab] {
        showsBoardTab ? LocationTab.allCases : [.newPlace]
    }

    var body: some View {
        VStack(spacing: 0) {
            if visibleTabs.count > 1 {
                Picker("Location source", selection: $selectedTab) {
                    ForEach(visibleTabs) { tab in
                        Text(tab.localizedTitle)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            if selectedTab == .newPlace {
                newPlaceContent
            } else {
                savedBoardsContent
            }
        }
        .overlay {
            if isPreparingMap {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()

                    ProgressView()
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // .background(.white)
        // No nav bar on the search root — the map's back chevron behind the
        // sheet handles cancel. The pushed board view keeps its own bar.
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await mapSearchService.configureWithUserLocation()
            await recentLocationService.fetchRecent()
            await mapSearchService.searchNearbyCombined(queries: [
                "restaurants", "cafes", "attractions",
            ])
            isInitialLoading = false
        }
        .task(id: searchText) {
            guard selectedTab == .newPlace else { return }
            try? await Task.sleep(for: .milliseconds(300))
            mapSearchService.updateQuery(searchText)
        }
        .task {
            await boardService.loadIfNeeded()
        }
    }

    // MARK: - Default Content

    private var newPlaceContent: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Search location")
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if isInitialLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                defaultContent
            } else {
                searchResultsList
            }
        }
    }

    private var hasRecentLocations: Bool {
        !recentLocationService.recentLocations.isEmpty
    }

    private var hasSuggestedLocations: Bool {
        mapSearchService.userLocation != nil && !mapSearchService.suggestedResults.isEmpty
    }

    private var defaultContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                if hasRecentLocations {
                    locationSection(
                        title: "Recently viewed",
                        items: recentLocationService.recentLocations.map { dto in
                            ChooseLocationItem(
                                id: String(dto.id),
                                title: dto.name,
                                address: dto.address ?? "",
                                imageName: dto.pointOfInterestCategory,
                                latitude: dto.latitude,
                                longitude: dto.longitude
                            )
                        }
                    )
                }

                if hasSuggestedLocations {
                    locationSection(
                        title: "Suggested for you",
                        items: mapSearchService.suggestedResults.map { result in
                            ChooseLocationItem(
                                id: result.id,
                                title: result.name,
                                address: result.address,
                                imageName: ChooseLocationItem.illustrationName(
                                    for: result.pointOfInterestCategory),
                                latitude: result.latitude,
                                longitude: result.longitude,
                                category: CategoryChip.Category.from(
                                    poiCategory: result.pointOfInterestCategory)?.apiValue
                            )
                        }
                    )
                }

                if mapSearchService.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else if !hasRecentLocations, !hasSuggestedLocations {
                    VStack(spacing: 16) {
                        Image("emptyHome")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200)

                        Text("Search for a place to get started")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentM)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Saved Boards

    private var savedBoardsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Boards")
                    .font(.beVietnamPro(16, weight: .medium))
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)

                if boardService.boards.isEmpty && boardService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if boardService.boards.isEmpty {
                    VStack(spacing: 12) {
                        Image("emptyHome")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160)

                        Text("You haven't created any boards yet.")
                            .font(.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentM)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(boardService.boards, id: \.id) { board in
                        savedBoardRow(board)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func savedBoardRow(_ board: BoardSummaryDto) -> some View {
        // The server already drops missing segments from locationLabel, so
        // the first comma-segment is the city → state → country fallback.
        let primaryLocation: String? = {
            guard let label = board.locationLabel,
                let first = label.split(separator: ",").first
            else { return nil }
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }()

        return NavigationLink {
            ChooseLocationBoardPinsView(
                board: board,
                tripId: tripId ?? 0,
                userId: userProfileService.profile?.id ?? 0,
                dayNumber: dayNumber,
                planDate: planDate,
                tripDetailService: tripDetailService,
                onBoardPinsSelected: onBoardPinsSelected
            ) {
                // Host's onPinsAddedToTrip dismisses the whole picker.
                onPinsAddedToTrip()
            }
        } label: {
            BoardSummaryRow(board: board, variant: .picker)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(board.title), \(board.pinCount) pins, \(primaryLocation ?? String(localized: "no location"))")
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(mapSearchService.completions, id: \.self) { completion in
                    Button {
                        Task { await selectCompletion(completion) }
                    } label: {
                        HStack(spacing: 12) {
                            Image("appLogoCutout")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(Font.custom("Be Vietnam Pro", size: 14))
                                    .foregroundColor(Constants.ContentB)
                                    .lineLimit(1)

                                Text(completion.subtitle)
                                    .font(Font.custom("Be Vietnam Pro", size: 14))
                                    .foregroundColor(Constants.ContentM)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Constants.DividerStroke)
                        .frame(height: 1)
                        .padding(.leading, 48)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Selection

    private func selectCompletion(_ completion: MKLocalSearchCompletion) async {
        guard !isPreparingMap else { return }
        guard let result = await mapSearchService.resolveCompletion(completion) else { return }

        let item = ChooseLocationItem(
            id: result.id,
            title: result.name,
            address: result.address,
            imageName: ChooseLocationItem.illustrationName(for: result.pointOfInterestCategory),
            latitude: result.latitude,
            longitude: result.longitude,
            category: CategoryChip.Category.from(poiCategory: result.pointOfInterestCategory)?
                .apiValue
        )

        Task {
            await recentLocationService.saveRecent(
                name: result.name,
                address: result.address,
                latitude: result.latitude,
                longitude: result.longitude,
                pointOfInterestCategory: ChooseLocationItem.illustrationName(
                    for: result.pointOfInterestCategory)
            )
        }

        await handleLocationSelection(item)
    }

    // MARK: - Section & Card Helpers

    private func locationSection(title: LocalizedStringKey, items: [ChooseLocationItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(items) { item in
                        locationCard(item)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func locationCard(_ item: ChooseLocationItem) -> some View {
        Button {
            guard !isPreparingMap else { return }
            Task {
                Task {
                    await recentLocationService.saveRecent(
                        name: item.title,
                        address: item.address,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        pointOfInterestCategory: item.imageName
                    )
                }
                await handleLocationSelection(item)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Constants.Neutral50)
                        .frame(width: 116, height: 116)

                    Image(item.imageName ?? "appLogoCutout")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(2)

                    Text(item.address)
                        .font(Font.custom("Be Vietnam Pro", size: 10))
                        .foregroundColor(Constants.ContentM)
                        .lineLimit(2)
                }
                .frame(width: 116, alignment: .leading)
            }
            .frame(width: 116, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func handleLocationSelection(_ item: ChooseLocationItem) async {
        guard let latitude = item.latitude, let longitude = item.longitude else {
            // No coordinates to fly to — hand off directly; the host decides
            // whether to commit or simply morph to a coordinate-less detail.
            onPlaceSelected(item)
            return
        }

        isPreparingMap = true
        defer { isPreparingMap = false }
        await MapWarmupService.warmup(latitude: latitude, longitude: longitude)

        // The host warms up complete; report the pick so it can fly the map
        // and morph the sheet to the detail surface.
        onPlaceSelected(item)
    }
}

#Preview {
    NavigationStack {
        ChooseLocationPickerContent()
    }
}

private struct ChooseLocationBoardPinsView: View {
    let board: BoardSummaryDto
    let tripId: Int
    let userId: Int
    let dayNumber: Int?
    let planDate: String?
    var tripDetailService: TripDetailService
    var onBoardPinsSelected: (([BoardPinDto]) -> Void)? = nil
    var onCompleted: () -> Void

    /// `dayNumber` wins if both are provided; otherwise falls back to day 1.
    private var resolvedDayNumber: Int? {
        if let dayNumber { return dayNumber }
        if planDate != nil { return nil }
        return 1
    }

    @State private var detail: BoardDto?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedPinIDs: Set<Int> = []
    @State private var searchText = ""
    @State private var isCommitting = false
    @State private var commitError: String?
    @State private var boardService = BoardService.shared
    @Environment(\.dismiss) private var dismiss

    private var pins: [BoardPinDto] { detail?.pins ?? [] }

    private var filteredPins: [BoardPinDto] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pins }
        return pins.filter { pin in
            pin.name.localizedStandardContains(trimmed)
                || (pin.address ?? "").localizedStandardContains(trimmed)
        }
    }

    private var allSelected: Bool {
        !pins.isEmpty && selectedPinIDs.count == pins.count
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                findSpotRow

                if isLoading && detail == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if loadError != nil && detail == nil {
                    ContentUnavailableView(
                        "Couldn't load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError ?? "")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else if pins.isEmpty {
                    ContentUnavailableView(
                        "No Pins",
                        systemImage: "mappin.slash",
                        description: Text("Saved places will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredPins, id: \.id) { pin in
                            Button {
                                togglePinSelection(pin)
                            } label: {
                                BoardPinRow(
                                    pin: pin,
                                    isSelected: selectedPinIDs.contains(pin.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(pin.name), \(pin.address ?? pin.notes ?? "")")
                            .accessibilityAddTraits(
                                selectedPinIDs.contains(pin.id) ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Constants.Neutral50.ignoresSafeArea()).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                selectAllButton
            }
            .sharedBackgroundHiddenCompat()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let commitError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(commitError)
                            .font(.custom("Be Vietnam Pro", size: 13))
                            .foregroundStyle(Constants.ContentB)
                        Spacer()
                        Button("Dismiss") { self.commitError = nil }
                            .font(.beVietnamPro(13, weight: .medium))
                    }
                    .padding(12)
                    .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 12)
                }

                if !selectedPinIDs.isEmpty {
                    PrimaryButton(
                        title: isCommitting
                            ? "Adding…"
                            // Pluralized in the String Catalog by the count argument.
                            : "Add \(selectedPinIDs.count) spots"
                    ) {
                        confirm()
                    }
                    .disabled(isCommitting)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: selectedPinIDs.isEmpty)
        .animation(.snappy(duration: 0.2), value: commitError)
        .task {
            await loadDetail()
        }
    }

    private var findSpotRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Constants.ContentB)
                .frame(width: 20, height: 20)

            TextField(
                "",
                text: $searchText,
                prompt: Text("Find spot").foregroundColor(Constants.ContentL)
            )
            .font(.custom("Be Vietnam Pro", size: 15))
            .foregroundStyle(Constants.ContentB)
            .submitLabel(.search)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var selectAllButton: some View {
        Button {
            toggleSelectAll()
        } label: {
            Text(allSelected ? String(localized: "Deselect all") : String(localized: "Select all"))
                .font(.beVietnamPro(15, weight: .medium))
                .foregroundStyle(Constants.ContentB)
                .padding(.horizontal, 14)
                .frame(height: 34)
        }
        .buttonStyle(.plain)
        .chooseLocationLiquidGlassButton()
        .accessibilityLabel(allSelected ? String(localized: "Deselect all spots") : String(localized: "Select all spots"))
        .disabled(pins.isEmpty || isCommitting)
    }

    private func togglePinSelection(_ pin: BoardPinDto) {
        if selectedPinIDs.contains(pin.id) {
            selectedPinIDs.remove(pin.id)
        } else {
            selectedPinIDs.insert(pin.id)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedPinIDs.removeAll()
        } else {
            selectedPinIDs = Set(pins.map(\.id))
        }
    }

    private func confirm() {
        let picked = pins.filter { selectedPinIDs.contains($0.id) }
        guard !picked.isEmpty, !isCommitting else { return }

        // Draft mode: hand the picked pins back to the caller (e.g. to append to
        // an in-memory marketplace draft) instead of writing them to a trip.
        if let onBoardPinsSelected {
            onBoardPinsSelected(picked)
            onCompleted()
            return
        }

        isCommitting = true
        commitError = nil
        Task {
            defer { isCommitting = false }
            do {
                for (offset, pin) in picked.enumerated() {
                    // Plan timeline filters items missing startTime — stagger
                    // 30 min from 09:00, clamp to 23:30 if N is huge.
                    let totalMinutes = min(9 * 60 + offset * 30, 23 * 60 + 30)
                    let hour = totalMinutes / 60
                    let minute = totalMinutes % 60
                    let startTime = String(format: "%02d:%02d", hour, minute)

                    let result = await tripDetailService.createPlanItem(
                        tripId: tripId,
                        title: pin.name,
                        planDate: planDate,
                        description: pin.notes,
                        location: pin.address,
                        latitude: pin.latitude,
                        longitude: pin.longitude,
                        address: pin.address,
                        startTime: startTime,
                        category: nil,
                        userIds: [userId],
                        voiceUrl: nil,
                        voiceDuration: nil,
                        dayNumber: resolvedDayNumber
                    )
                    if case .failure(let error) = result { throw error }
                }
                NotificationCenter.default.post(
                    name: .marketplacePlanApplied,
                    object: tripId
                )
                onCompleted()
            } catch {
                print("ChooseLocationBoardPinsView.confirm error: \(error)")
                commitError = String(localized: "Couldn't add these pins to the trip.")
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await boardService.getBoard(boardId: board.id)
            loadError = nil
        } catch {
            print("ChooseLocationBoardPinsView.loadDetail error: \(error)")
            loadError = String(localized: "Couldn't load this board.")
        }
    }
}

private struct ChooseLocationLiquidGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    fileprivate func chooseLocationLiquidGlassButton() -> some View {
        modifier(ChooseLocationLiquidGlassButton())
    }
}
