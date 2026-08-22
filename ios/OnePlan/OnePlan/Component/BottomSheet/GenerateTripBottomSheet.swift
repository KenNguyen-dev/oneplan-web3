//
//  GenerateTripBottomSheet.swift
//  OnePlan
//
//  Lets the user turn a board's pins into a brand-new AI-arranged trip:
//  pick which pins to include, how many days, and a trip name, then tap
//  Generate. The server groups the selected pins across the chosen days.
//

import CoreLocation
import SwiftUI

struct GenerateTripBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let boardId: Int
    let boardName: String
    let pins: [BoardPinDto]
    // True when the backing board has no location yet (the auto-created board
    // in ProcessPinView's New Trip flow): shows a required Location field and
    // writes the choice onto the board before generating, since the generated
    // trip's destination comes from the board.
    var asksForLocation: Bool
    var onGenerated: (TripDto) -> Void

    @State private var tripName: String
    @State private var selectedCity: CityDto?
    @State private var selectedState: StateDto?
    @State private var selectedCountry: CountryDto?
    @State private var showLocationPicker = false
    @State private var selectedPinIds: Set<Int>
    @State private var dayCount: Int
    // Opt-in: let the AI add clearly-marked suggested venues to fill empty
    // meal/sightseeing slots. OFF by default — the plan uses only the user's
    // pins unless they explicitly ask.
    @State private var fillGaps = false
    // Once the user nudges the stepper we stop auto-deriving the day count
    // from the selection, so their choice sticks.
    @State private var dayCountTouched = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var loadingMessageIndex = 0

    // Cycled under the spinner while the AI request is in flight so a multi-
    // second wait feels alive rather than frozen.
    private let loadingMessages: [LocalizedStringKey] = [
        "Arranging your pins by area…",
        "Planning your days…",
        "Setting start times…",
        "Almost there…",
    ]

    private let maxDays = 14
    // Above this straight-line distance between any two selected pins we treat
    // the selection as spanning separate regions (e.g. Vietnam + Japan) and warn
    // the user. Set above Vietnam's own ~1,150 km Hanoi–HCMC span so a legit
    // long domestic trip doesn't false-trigger, while cross-country jumps do.
    private static let farApartThresholdKm = 1_500.0

    init(
        boardId: Int,
        boardName: String,
        pins: [BoardPinDto],
        asksForLocation: Bool = false,
        onGenerated: @escaping (TripDto) -> Void
    ) {
        self.boardId = boardId
        self.boardName = boardName
        self.pins = pins
        self.asksForLocation = asksForLocation
        self.onGenerated = onGenerated
        _tripName = State(initialValue: boardName)
        // Start with nothing selected — the user explicitly picks which pins
        // go into the trip.
        _selectedPinIds = State(initialValue: [])
        _dayCount = State(initialValue: Self.suggestedDays(for: 0))
    }

    // ceil(pins / 4): a relaxed pace of ~4 stops a day, clamped to 1...14.
    private static func suggestedDays(for pinCount: Int) -> Int {
        guard pinCount > 0 else { return 1 }
        let suggested = Int(ceil(Double(pinCount) / 4.0))
        return min(max(suggested, 1), 14)
    }

    private var selectedCount: Int { selectedPinIds.count }
    private var dayUpperBound: Int { max(1, min(maxDays, selectedCount)) }

    // Coordinates of the selected pins that actually have a location. Pins whose
    // enrichment failed (no lat/lng) can't be placed geographically, so they're
    // excluded from the spread check.
    private var selectedCoordinates: [(lat: Double, lng: Double)] {
        pins
            .filter { selectedPinIds.contains($0.id) }
            .compactMap { pin in
                guard let lat = pin.latitude, let lng = pin.longitude else {
                    return nil
                }
                return (lat, lng)
            }
    }

    // True when any two selected pins are farther apart than the threshold —
    // a cheap O(n²) max-pairwise scan (n ≤ 40) that early-exits on the first hit.
    private var selectedPinsSpanFarApart: Bool {
        let coords = selectedCoordinates
        guard coords.count >= 2 else { return false }
        for i in 0..<coords.count {
            for j in (i + 1)..<coords.count
            where Self.haversineKm(coords[i], coords[j])
                > Self.farApartThresholdKm {
                return true
            }
        }
        return false
    }

    private static func haversineKm(
        _ a: (lat: Double, lng: Double),
        _ b: (lat: Double, lng: Double)
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let h =
            sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }
    private var trimmedName: String {
        tripName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasRequiredLocation: Bool {
        !asksForLocation || (selectedState != nil && selectedCountry != nil)
    }
    private var displayLocationLabel: String? {
        let parts = [selectedCity?.name, selectedState?.name, selectedCountry?.name]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    private var canGenerate: Bool {
        selectedCount > 0 && !trimmedName.isEmpty && hasRequiredLocation
            && !isGenerating
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 24)
                .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 22) {
                    nameField
                    if asksForLocation {
                        locationField
                    }
                    dayStepper
                    // AI suggestions (fill gaps) hidden for now — `fillGaps`
                    // stays false so generation uses only the user's pins.
                    // fillGapsToggle
                    if selectedPinsSpanFarApart {
                        farApartWarning
                    }
                    pinSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                // Room for the floating Generate button so the last pin can
                // still scroll clear of it.
                .padding(.bottom, 84)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) { footer }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Neutral50)
        .blur(radius: isGenerating ? 3 : 0)
        .disabled(isGenerating)
        .overlay {
            if isGenerating {
                generatingOverlay.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isGenerating)
        .interactiveDismissDisabled(isGenerating)
        .presentationDetents([.large])
        .presentationDragIndicator(isGenerating ? .hidden : .visible)
        .fullScreenCover(isPresented: $showLocationPicker) {
            TripLocationPickerSheet(isPresented: $showLocationPicker) { city, state, country in
                selectedCity = city
                selectedState = state
                selectedCountry = country
            }
        }
        .onChange(of: selectedPinIds) { _, _ in
            if !dayCountTouched {
                dayCount = Self.suggestedDays(for: selectedCount)
            }
            dayCount = min(max(dayCount, 1), dayUpperBound)
        }
        .alert(
            "Couldn't generate trip",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Generate a trip")
                .font(.custom("Be Vietnam Pro", size: 20))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.8)
                .lineLimit(1)

            Text("We'll arrange your pins into a day-by-day plan.")
                .font(.custom("Be Vietnam Pro", size: 13))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.65)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Trip name")
            TextField("Trip name", text: $tripName)
                .font(.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Constants.ContentB)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    Constants.White,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .submitLabel(.done)
        }
    }

    // Styled like CreateBoardBottomSheet's locationRow — a required field that
    // opens TripLocationPickerSheet.
    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Location")
            Button {
                showLocationPicker = true
            } label: {
                HStack(spacing: 12) {
                    Text(displayLocationLabel ?? String(localized: "Choose a destination"))
                        .font(.beVietnamPro(16))
                        .tracking(-0.32)
                        .foregroundStyle(
                            displayLocationLabel == nil
                                ? Constants.ContentL : Constants.ContentB
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Constants.ContentL)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    Constants.White,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location")
            .accessibilityValue(displayLocationLabel ?? "Not set")
        }
    }

    private var dayStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Trip length")
            HStack(spacing: 12) {
                Text(dayCount == 1 ? "1 day" : "\(dayCount) days")
                    .font(.beVietnamPro(16, weight: .medium))
                    .tracking(-0.32)
                    .foregroundStyle(Constants.ContentB)

                Spacer(minLength: 0)

                stepperButton(systemName: "minus", enabled: dayCount > 1) {
                    adjustDays(by: -1)
                }
                stepperButton(
                    systemName: "plus",
                    enabled: dayCount < dayUpperBound
                ) {
                    adjustDays(by: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Constants.White,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private var fillGapsToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("AI suggestions")
            Toggle(isOn: $fillGaps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fill meals & gaps with AI suggestions")
                        .font(.beVietnamPro(16, weight: .medium))
                        .tracking(-0.32)
                        .foregroundStyle(Constants.ContentB)
                    Text("Suggested places are clearly marked and easy to remove.")
                        .font(.beVietnamPro(13))
                        .tracking(-0.26)
                        .foregroundStyle(Constants.ContentM)
                }
            }
            .tint(Constants.BlueBase)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Constants.White,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private func stepperButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? Constants.White : Constants.ContentL)
                .frame(width: 32, height: 32)
                .background(
                    enabled ? Constants.BlueBase : Constants.Neutral100,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "plus" ? "Add a day" : "Remove a day")
    }

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                fieldLabel("Places")
                Spacer(minLength: 0)
                Text("\(selectedCount) of \(pins.count) selected")
                    .font(.beVietnamPro(13))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.26)
                Button(allSelected ? "Deselect all" : "Select all") {
                    toggleSelectAll()
                }
                .font(.beVietnamPro(13, weight: .medium))
                .foregroundStyle(Constants.BlueBase)
                .tracking(-0.26)
                .buttonStyle(.plain)
            }

            LazyVStack(spacing: 8) {
                ForEach(pins, id: \.id) { pin in
                    Button {
                        togglePin(pin.id)
                    } label: {
                        BoardPinRow(
                            pin: pin,
                            isSelected: selectedPinIds.contains(pin.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pin.name)
                    .accessibilityAddTraits(
                        selectedPinIds.contains(pin.id) ? [.isSelected] : []
                    )
                }
            }
        }
    }

    // Floats over the scroll content (content scrolls underneath; the scroll
    // view reserves matching bottom padding).
    private var footer: some View {
        PrimaryButton(title: "Generate trip") { generate() }
            .disabled(!canGenerate)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private var generatingOverlay: some View {
        ZStack {
            Constants.Neutral50.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Constants.BlueBase)

                Text("Generating your trip…")
                    .font(.beVietnamPro(17, weight: .medium))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.34)

                Text(loadingMessages[loadingMessageIndex])
                    .font(.beVietnamPro(14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.28)
                    .multilineTextAlignment(.center)
                    .id(loadingMessageIndex)
                    .transition(.opacity)
            }
            .padding(24)
        }
        .task {
            // Runs only while the overlay is shown; auto-cancelled on dismiss.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.3)) {
                    loadingMessageIndex =
                        (loadingMessageIndex + 1) % loadingMessages.count
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating your trip")
    }

    private var farApartWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Constants.Warning500)
            Text(
                "Some of these places are in different regions. They'll be grouped by area across your days — add more days or deselect distant pins for a tighter plan."
            )
            .font(.beVietnamPro(13))
            .foregroundStyle(Constants.ContentM)
            .tracking(-0.26)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Constants.Warning500.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.beVietnamPro(16, weight: .medium))
            .foregroundStyle(Constants.ContentM)
            .tracking(-0.32)
    }

    private var allSelected: Bool {
        !pins.isEmpty && selectedPinIds.count == pins.count
    }

    private func toggleSelectAll() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedPinIds = allSelected ? [] : Set(pins.map(\.id))
        }
    }

    private func togglePin(_ id: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.18)) {
            if selectedPinIds.contains(id) {
                selectedPinIds.remove(id)
            } else {
                selectedPinIds.insert(id)
            }
        }
    }

    private func adjustDays(by delta: Int) {
        dayCountTouched = true
        dayCount = min(max(dayCount + delta, 1), dayUpperBound)
    }

    private func generate() {
        guard canGenerate else { return }
        let name = trimmedName
        let ids = Array(selectedPinIds)
        let days = min(max(dayCount, 1), dayUpperBound)
        Task {
            isGenerating = true
            defer { isGenerating = false }
            do {
                // The generated trip's destination comes from the board, so
                // persist the chosen location onto the board first.
                if asksForLocation, let state = selectedState,
                   let country = selectedCountry {
                    _ = try await BoardService.shared.updateBoard(
                        boardId: boardId,
                        title: boardName,
                        cityId: selectedCity?.id,
                        stateId: state.id,
                        countryId: country.id
                    )
                }
                let trip = try await BoardService.shared.generateTrip(
                    boardId: boardId,
                    pinIds: ids,
                    dayCount: days,
                    tripName: name,
                    fillGaps: fillGaps
                )
                if fillGaps {
                    await enrichSuggestedItems(trip: trip)
                }
                onGenerated(trip)
                dismiss()
            } catch {
                print("GenerateTripBottomSheet.generate error: \(error)")
                errorMessage = String(
                    localized: "Couldn't generate your trip. Please try again."
                )
            }
        }
    }

    // AI-suggested plan items carry LLM-guessed venues: names can be
    // hallucinated outright and coordinates are often a shared city-centre
    // placeholder. Apple Maps is the gatekeeper — each suggestion is strictly
    // verified (name-resembling POI inside the trip's region); verified ones
    // get the canonical name/address/coordinate persisted, unverifiable ones
    // are DELETED from the plan rather than shown at a made-up location.
    private func enrichSuggestedItems(trip: TripDto) async {
        let tripId = Int(trip.id)
        let client = APIClient.shared
        guard
            let items = try? await client.listPlanItems(
                .init(path: .init(tripId: tripId), query: .init())
            ).ok.body.json
        else { return }

        let tripLocation = trip.location?.value1
        let city = tripLocation?.cityName ?? tripLocation?.stateName
        let country = tripLocation?.countryName

        let enricher = PinEnrichmentService()
        for item in items
        where item.description?.hasPrefix("✨ Suggested") == true {
            let itemId = Int(item.id)
            if let match = await enricher.enrichStrict(
                name: item.title,
                city: city,
                country: country
            ) {
                _ = try? await client.updatePlanItem(.init(
                    path: .init(tripId: tripId, id: itemId),
                    body: .json(.init(
                        title: match.name,
                        location: match.address,
                        latitude: match.coordinate.latitude,
                        longitude: match.coordinate.longitude,
                        address: match.address
                    ))
                ))
            } else {
                _ = try? await client.deletePlanItem(
                    .init(path: .init(tripId: tripId, id: itemId))
                )
            }
        }
    }
}
