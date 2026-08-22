//
//  UploadTripFormView.swift
//  OnePlan
//

import SwiftUI

enum MarketplaceEditorDayMapper {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static let baseDate: Date = {
        guard let date = formatter.date(from: "2026-01-01") else {
            fatalError("Failed to create marketplace editor base date")
        }
        return date
    }()

    static func planDate(forDayNumber dayNumber: Int) -> String {
        let safeDayNumber = max(dayNumber, 1)
        let date =
            calendar.date(
                byAdding: .day,
                value: safeDayNumber - 1,
                to: baseDate
            ) ?? baseDate
        return formatter.string(from: date)
    }

    static func dayNumber(forPlanDate planDate: String?) -> Int? {
        guard let planDate,
            let date = formatter.date(from: planDate)
        else {
            return nil
        }

        let dayOffset =
            calendar.dateComponents(
                [.day],
                from: baseDate,
                to: date
            ).day ?? 0
        return max(dayOffset + 1, 1)
    }

    static func normalizedPlanItems(_ items: [PlanItemDto]) -> [PlanItemDto] {
        let sortedDates = Array(Set(items.compactMap(\.planDate))).sorted()
        let dateToDayNumber = Dictionary(
            uniqueKeysWithValues: sortedDates.enumerated().map { index, date in
                (date, index + 1)
            }
        )

        return items.map { item in
            var normalizedItem = item
            if let rawPlanDate = item.planDate,
                let dayNumber = dateToDayNumber[rawPlanDate]
            {
                normalizedItem.planDate = Self.planDate(forDayNumber: dayNumber)
            }
            return normalizedItem
        }
    }
}

@MainActor
enum UploadTripPublishSuccess {
    case created
    case updated(ListingUpdateInfo)
}

/// Comparable snapshot of the upload form's editable state, used to detect
/// unsaved changes. Excludes `planItemImagesById` (populated lazily when an
/// item is opened, so not a reliable user-intent signal).
private struct EditorBaseline: Equatable {
    let planName: String
    let descriptionText: String
    let priceText: String
    let selectedTag: Components.Schemas.ListingTag
    let selectedCurrency: Currency
    let durationDaysValue: Int
    let planItems: [PlanItemDto]
    let cityId: Int?
    let stateId: Int?
    let countryId: Int?
    let hasCoverImage: Bool
}

@MainActor
@Observable
final class UploadTripEditorModel {
    static let maxDurationDays = 30

    enum Mode {
        case create(service: TripDetailService, tripId: Int?)
        case edit(listingId: Int)
    }

    let mode: Mode

    var listingDetailService = MarketplaceListingDetailService()
    var marketplaceService = MarketplaceService()

    var planName: String = ""
    var descriptionText: String = ""
    var priceText: String = ""
    var selectedTag: Components.Schemas.ListingTag = .SOLO
    var isShowingTagPicker = false
    var selectedCurrency: Currency = .VND
    var isShowingCurrencyPicker = false
    var allPlanItems: [PlanItemDto] = []
    var durationDaysValue: Int = 1
    var coverImage: UIImage?
    var isShowingLocationPicker = false
    var pickedCity: CityDto?
    var pickedState: StateDto?
    var pickedCountry: CountryDto?

    var isShowingCreatePlan = false
    var editingPlanItem: PlanItemDto?
    var navPlanName: String = ""
    var navMessage: String = ""
    var navSelectedDayIndex: Int = 0
    var navTimeText: String = "08:00"
    var navLocationText: String = ""
    var submissionErrorMessage: String?

    var prefilledTripId: Int?
    var prefilledListingId: Int?
    var planItemImagesById: [Int: [UIImage]] = [:]
    var planItemImageUrlsById: [Int: [String]] = [:]

    /// Snapshot of the editable state captured once the form is prefilled, used
    /// to detect unsaved changes when the user tries to leave.
    private var baseline: EditorBaseline?

    init(mode: Mode) {
        self.mode = mode
    }

    var tripId: Int? {
        switch mode {
        case .create(_, let tripId):
            return tripId
        case .edit:
            return nil
        }
    }

    var editingListingId: Int? {
        switch mode {
        case .create:
            return nil
        case .edit(let listingId):
            return listingId
        }
    }

    private var tripService: TripDetailService? {
        switch mode {
        case .create(let service, _):
            return service
        case .edit:
            return nil
        }
    }

    var prefillTaskId: Int {
        editingListingId ?? tripId ?? 0
    }

    var coverImageUrl: String? {
        if editingListingId != nil {
            return listingDetailService.listing?.coverImageUrl
        }
        return tripService?.trip?.coverImageUrl
    }

    var locationName: String {
        if let state = pickedState, let country = pickedCountry {
            return [pickedCity?.name, state.name, country.name]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
        return ""
    }

    var cityId: Int? {
        pickedCity?.id
    }

    var stateId: Int? {
        pickedState?.id
    }

    var countryId: Int? {
        pickedCountry?.id
    }

    var durationDays: Int {
        max(1, min(durationDaysValue, Self.maxDurationDays))
    }

    var availableDayNumbers: [Int] {
        Array(1...durationDays)
    }

    var highestDayWithPlans: Int {
        allPlanItems.compactMap { item in
            MarketplaceEditorDayMapper.dayNumber(forPlanDate: item.planDate)
        }
        .max() ?? 0
    }

    var dayLabels: [String] {
        availableDayNumbers.map { "Day \($0)" }
    }

    func prefillIfNeeded() async {
        if let listingId = editingListingId {
            guard prefilledListingId != listingId else { return }
            prefilledListingId = listingId
            await prefillFromListing(listingId)
        } else if let tripId {
            guard prefilledTripId != tripId else { return }
            prefilledTripId = tripId
            await prefillFromTrip()
        }
        // When tripId is nil: form stays empty (create from scratch)

        // Capture the baseline once, after any prefill, so dirtiness is measured
        // against the initial (prefilled or empty) state.
        if baseline == nil {
            baseline = makeSnapshot()
        }
    }

    /// True when the editable state differs from the captured baseline — i.e. the
    /// user has typed, picked, or added/edited plans that would be lost on leave.
    var hasUnsavedChanges: Bool {
        guard let baseline else {
            // Baseline not captured yet (prefill in flight) — fall back to a
            // plain content check.
            return !allPlanItems.isEmpty
                || !planName.isEmpty
                || !descriptionText.isEmpty
                || !priceText.isEmpty
                || coverImage != nil
                || cityId != nil
                || stateId != nil
                || countryId != nil
        }
        return makeSnapshot() != baseline
    }

    private func makeSnapshot() -> EditorBaseline {
        EditorBaseline(
            planName: planName,
            descriptionText: descriptionText,
            priceText: priceText,
            selectedTag: selectedTag,
            selectedCurrency: selectedCurrency,
            durationDaysValue: durationDaysValue,
            planItems: allPlanItems,
            cityId: cityId,
            stateId: stateId,
            countryId: countryId,
            hasCoverImage: coverImage != nil
        )
    }

    func openForNewPlan(dayNumber: Int = 1) {
        editingPlanItem = nil
        navPlanName = ""
        navMessage = ""
        navTimeText = "08:00"
        navLocationText = ""
        navSelectedDayIndex = min(
            max(dayNumber - 1, 0),
            max(durationDays - 1, 0)
        )
        isShowingCreatePlan = true
    }

    func openForEditing(_ item: PlanItemDto) {
        editingPlanItem = item
        navPlanName = item.title
        navMessage = item.description ?? ""
        navTimeText = item.startTime ?? "08:00"
        navLocationText = item.location ?? ""
        navSelectedDayIndex = max(
            (MarketplaceEditorDayMapper.dayNumber(forPlanDate: item.planDate)
                ?? 1) - 1,
            0
        )
        isShowingCreatePlan = true
    }

    var canAddDay: Bool {
        durationDays < Self.maxDurationDays
    }

    func addDay() {
        guard canAddDay else { return }
        durationDaysValue += 1
    }

    func deleteDay(_ day: Int) {
        guard durationDays > 1, day >= 1, day <= durationDays else { return }
        let newDuration = max(durationDays - 1, 1)

        let removedIds = Set(
            allPlanItems.compactMap { item -> Int? in
                guard
                    MarketplaceEditorDayMapper.dayNumber(
                        forPlanDate: item.planDate
                    ) == day
                else {
                    return nil
                }
                return item.id
            }
        )

        allPlanItems = allPlanItems.compactMap { item in
            guard
                let currentDay = MarketplaceEditorDayMapper.dayNumber(
                    forPlanDate: item.planDate
                )
            else {
                return nil
            }
            if currentDay == day {
                return nil
            }

            var updatedItem = item
            if currentDay > day {
                updatedItem.planDate = MarketplaceEditorDayMapper.planDate(
                    forDayNumber: currentDay - 1
                )
            }
            return updatedItem
        }

        planItemImagesById = planItemImagesById.filter {
            !removedIds.contains($0.key)
        }
        planItemImageUrlsById = planItemImageUrlsById.filter {
            !removedIds.contains($0.key)
        }
        durationDaysValue = newDuration

        if let editingPlanItem, removedIds.contains(editingPlanItem.id) {
            self.editingPlanItem = nil
            isShowingCreatePlan = false
        } else {
            if navSelectedDayIndex + 1 == day {
                navSelectedDayIndex = max(day - 2, 0)
            } else if navSelectedDayIndex + 1 > day {
                navSelectedDayIndex -= 1
            } else {
                navSelectedDayIndex = min(
                    navSelectedDayIndex,
                    max(newDuration - 1, 0)
                )
            }
        }
    }

    func formatPrice(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty, let number = Int(digits) else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? digits
    }

    func publish() async -> UploadTripPublishSuccess? {
        let price = Double(priceText.filter(\.isNumber)) ?? 0
        let success: Bool
        guard let apiCurrency = selectedCurrency.toAPICurrency else {
            submissionErrorMessage = String(localized: "Unsupported currency")
            return nil
        }

        if let listingId = editingListingId {
            let existingItemIds = Set(
                listingDetailService.listing?.items.map(\.id) ?? []
            )
            let updateResult = await marketplaceService.updateTrip(
                listingId: listingId,
                name: planName,
                description: descriptionText.isEmpty ? nil : descriptionText,
                selectedCoverImage: coverImage,
                cityId: cityId,
                stateId: stateId,
                countryId: countryId,
                price: price,
                currency: apiCurrency,
                durationDays: durationDays,
                tags: [selectedTag],
                planItems: allPlanItems,
                existingItemIds: existingItemIds,
                planItemImagesById: planItemImagesById
            )

            guard let updateResult else { return nil }

            let info = ListingUpdateInfo(
                listingId: listingId,
                name: planName,
                rawPrice: String(Int(price)),
                currency: selectedCurrency,
                tags: [selectedTag],
                durationDays: durationDays,
                coverImageUrl: coverImage != nil ? updateResult.coverImageUrl : nil
            )
            return .updated(info)
        }

        success = await marketplaceService.publishTrip(
            name: planName,
            description: descriptionText.isEmpty ? nil : descriptionText,
            selectedCoverImage: coverImage,
            coverImageUrl: coverImageUrl,
            cityId: cityId,
            stateId: stateId,
            countryId: countryId,
            price: price,
            currency: apiCurrency,
            durationDays: durationDays,
            tags: [selectedTag],
            planItems: allPlanItems,
            planItemImagesById: planItemImagesById
        )

        return success ? .created : nil
    }

    private func prefillFromListing(_ listingId: Int) async {
        await listingDetailService.fetchListing(id: listingId)
        guard let listing = listingDetailService.listing else { return }

        planName = listing.name
        descriptionText = listing.description ?? ""
        priceText = listing.price
        selectedTag = listing.tags.first ?? .SOLO
        selectedCurrency = Currency(from: listing.currency.value1) ?? .VND
        durationDaysValue = listing.durationDays

        if let countryId = listing.countryId, let countryName = listing.countryName {
            pickedCountry = CountryDto(
                id: countryId,
                name: countryName,
                iso2: nil,
                iso3: nil,
                phoneCode: nil,
                capital: nil,
                currency: nil,
                region: nil,
                subRegion: nil,
                emoji: nil
            )
        } else {
            pickedCountry = nil
        }

        if let stateId = listing.stateId, let stateName = listing.stateName {
            pickedState = StateDto(
                id: stateId,
                latitude: nil,
                longitude: nil,
                name: stateName,
                iso2: nil,
                _type: nil
            )
        } else {
            pickedState = nil
        }

        if let cityId = listing.cityId, let cityName = listing.cityName {
            pickedCity = CityDto(
                id: cityId,
                latitude: "",
                longitude: "",
                name: cityName
            )
        } else {
            pickedCity = nil
        }

        planItemImagesById = [:]
        var imageUrlsById: [Int: [String]] = [:]
        for item in listing.items {
            imageUrlsById[item.id] = item.imageUrls
        }
        planItemImageUrlsById = imageUrlsById

        allPlanItems = listing.items.map { item in
            Components.Schemas.PlanItemDto(
                id: item.id,
                tripId: 0,
                planDate: MarketplaceEditorDayMapper.planDate(
                    forDayNumber: item.dayNumber
                ),
                title: item.title,
                description: item.description,
                location: item.location,
                latitude: item.latitude,
                longitude: item.longitude,
                address: item.address,
                startTime: item.startTime,
                category: item.category.map { .init(value1: $0.value1) },
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: nil,
                sortOrder: item.sortOrder,
                createdAt: item.createdAt,
                members: []
            )
        }
    }

    private func prefillFromTrip() async {
        guard let tripId else { return }
        planName = ""
        await tripService?.fetchAllTripPlanItems(tripId: tripId, force: true)
        let items = tripService?.allPlanItems ?? []
        allPlanItems = MarketplaceEditorDayMapper.normalizedPlanItems(items)
        planItemImagesById = [:]
        planItemImageUrlsById = [:]

        if let tripCurrency = tripService?.trip?.currency.value1,
            let currency = Currency(from: tripCurrency)
        {
            selectedCurrency = currency
        }

        if let location = tripService?.trip?.location?.value1 {
            if let countryId = location.countryId,
                let countryName = location.countryName
            {
                pickedCountry = CountryDto(
                    id: countryId,
                    name: countryName,
                    iso2: nil,
                    iso3: nil,
                    phoneCode: nil,
                    capital: nil,
                    currency: nil,
                    region: nil,
                    subRegion: nil,
                    emoji: nil
                )
            } else {
                pickedCountry = nil
            }

            if let stateId = location.stateId, let stateName = location.stateName
            {
                pickedState = StateDto(
                    id: stateId,
                    latitude: nil,
                    longitude: nil,
                    name: stateName,
                    iso2: nil,
                    _type: nil
                )
            } else {
                pickedState = nil
            }

            if let cityId = location.cityId, let cityName = location.cityName {
                pickedCity = CityDto(
                    id: cityId,
                    latitude: "",
                    longitude: "",
                    name: cityName
                )
            } else {
                pickedCity = nil
            }
        }

        durationDaysValue = max(highestDayWithPlans, 1)
    }

}

struct UploadTripFormView: View {
    @State private var model: UploadTripEditorModel
    @State private var isShowingDeleteListingAlert = false
    @State private var deleteListingErrorMessage: String?
    @State private var isShowingDiscardAlert = false

    private let onClose: () -> Void
    private let onPublishSuccess: (UploadTripPublishSuccess) -> Void
    private let onDeleteSuccess: (() -> Void)?

    init(
        mode: UploadTripEditorModel.Mode,
        onClose: @escaping () -> Void,
        onPublishSuccess: @escaping (UploadTripPublishSuccess) -> Void,
        onDeleteSuccess: (() -> Void)? = nil
    ) {
        self._model = State(initialValue: UploadTripEditorModel(mode: mode))
        self.onClose = onClose
        self.onPublishSuccess = onPublishSuccess
        self.onDeleteSuccess = onDeleteSuccess
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 19) {
                MarketplaceThumbnailImageHolder(
                    thumbnailUrl: model.coverImageUrl,
                    thumbnailImage: model.coverImage,
                    editable: true,
                    onImageSelected: { image in
                        model.coverImage = image
                    }
                )

                VStack(alignment: .leading, spacing: 10) {
                    editableSummarySection

                    planDescriptionSection
                }
                .padding(12)
                .background(Constants.Surface)
                .clipShape(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity)

            MarketPlanSection(
                planItems: model.allPlanItems,
                mode: .full,
                availableDayNumbers: model.availableDayNumbers,
                durationDays: model.durationDays,
                canAddDay: model.canAddDay,
                showEmptyImagePlaceholder: true,
                planItemImagesById: model.planItemImagesById,
                planItemImageUrlsById: model.planItemImageUrlsById,
                dayNumberForPlanItem: { item in
                    MarketplaceEditorDayMapper.dayNumber(
                        forPlanDate: item.planDate
                    )
                },
                onPlanTapped: { item in
                    model.openForEditing(item)
                },
                onAddPlanTapped: { dayNumber in
                    model.openForNewPlan(dayNumber: dayNumber)
                },
                onAddDay: model.canAddDay
                    ? {
                        model.addDay()
                    } : nil,
                onDeleteDay: { dayNumber in
                    model.deleteDay(dayNumber)
                }
            )
            .padding(.top, 20)
        }
        .disabled(model.marketplaceService.isPublishing)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
        .safeAreaPadding(.horizontal, 16)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if model.hasUnsavedChanges {
                        isShowingDiscardAlert = true
                    } else {
                        onClose()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Constants.ContentB)
                }
                .contentShape(Circle())
                .disabled(model.marketplaceService.isPublishing)
                .opacity(model.marketplaceService.isPublishing ? 0.4 : 1)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.marketplaceService.isPublishing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Constants.BlueBase)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11.5)
                } else {
                    GlassContainerCompat {
                        HStack(spacing: -4) {
                            if model.editingListingId != nil {
                                ToolbarIconButton(
                                    systemName: "trash",
                                    foregroundColor: Constants.Warning500,
                                    horizontalPadding: 13
                                ) {
                                    isShowingDeleteListingAlert = true
                                }
                            }

                            ToolbarIconButton(
                                systemName: "checkmark",
                                foregroundColor: Constants.BlueBase,
                                horizontalPadding: 13,
                                verticalPadding: 13
                            ) {
                                Task {
                                    if let success = await model.publish() {
                                        onPublishSuccess(success)
                                    }
                                }
                            }
                            .opacity(canSubmitListing ? 1 : 0.4)
                            .disabled(!canSubmitListing)
                            .allowsHitTesting(canSubmitListing)
                        }
                    }
                }
            }
            .sharedBackgroundHiddenCompat()
        }
        .navigationBarBackButtonHidden(true)
        .background {
            ZStack(alignment: .top) {
                Color(Constants.Background)
                    .ignoresSafeArea()

                topBlurBackground
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .background(Constants.Background)
        .task(id: model.prefillTaskId) {
            await model.prefillIfNeeded()
        }
        .alert(
            "Delete this marketplace plan?",
            isPresented: $isShowingDeleteListingAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let listingId = model.editingListingId else { return }
                Task {
                    let success = await model.marketplaceService.deleteListing(
                        listingId: listingId
                    )
                    if success {
                        onDeleteSuccess?()
                    } else {
                        deleteListingErrorMessage =
                            String(localized: "Failed to delete marketplace plan. Please try again.")
                    }
                }
            }
        } message: {
            Text(
                "This will permanently remove the marketplace plan and all of its items."
            )
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { deleteListingErrorMessage != nil },
                set: { if !$0 { deleteListingErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                deleteListingErrorMessage = nil
            }
        } message: {
            Text(deleteListingErrorMessage ?? "Something went wrong.")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.submissionErrorMessage != nil },
                set: { if !$0 { model.submissionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.submissionErrorMessage = nil
            }
        } message: {
            Text(model.submissionErrorMessage ?? "Something went wrong.")
        }
        .alert("Discard changes?", isPresented: $isShowingDiscardAlert) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                onClose()
            }
        } message: {
            Text("All your changes will be lost.")
        }
        .navigationDestination(isPresented: isShowingCreatePlanBinding) {
            CreateMarketPlanView(
                allPlanItems: allPlanItemsBinding,
                editingPlanItem: editingPlanItemBinding,
                isPresented: isShowingCreatePlanBinding,
                planItemImagesById: planItemImagesByIdBinding,
                planName: model.navPlanName,
                message: model.navMessage,
                selectedDayIndex: model.navSelectedDayIndex,
                days: model.dayLabels,
                timeText: model.navTimeText,
                locationText: model.navLocationText,
                planItemImageUrlsById: model.planItemImageUrlsById,
                tripId: model.tripId ?? 0
            )
        }
        .sheet(isPresented: isShowingTagPickerBinding) {
            TagPickerBottomSheet(
                selectedTag: selectedTagBinding
            )
        }
        .sheet(isPresented: isShowingCurrencyPickerBinding) {
            CurrencyPickerBottomSheet(
                selectedCurrency: selectedCurrencyBinding
            )
        }
        .fullScreenCover(isPresented: isShowingLocationPickerBinding) {
            TripLocationPickerSheet(
                isPresented: isShowingLocationPickerBinding,
                onLocationSelected: { city, state, country in
                    model.pickedCity = city
                    model.pickedState = state
                    model.pickedCountry = country
                }
            )
        }
    }

    private var planNameBinding: Binding<String> {
        Binding(
            get: { model.planName },
            set: { model.planName = $0 }
        )
    }

    private var priceTextBinding: Binding<String> {
        Binding(
            get: { model.priceText },
            set: { model.priceText = $0 }
        )
    }

    private var descriptionTextBinding: Binding<String> {
        Binding(
            get: { model.descriptionText },
            set: { model.descriptionText = $0 }
        )
    }

    private var allPlanItemsBinding: Binding<[PlanItemDto]> {
        Binding(
            get: { model.allPlanItems },
            set: { model.allPlanItems = $0 }
        )
    }

    private var editingPlanItemBinding: Binding<PlanItemDto?> {
        Binding(
            get: { model.editingPlanItem },
            set: { model.editingPlanItem = $0 }
        )
    }

    private var planItemImagesByIdBinding: Binding<[Int: [UIImage]]> {
        Binding(
            get: { model.planItemImagesById },
            set: { model.planItemImagesById = $0 }
        )
    }

    private var isShowingCreatePlanBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingCreatePlan },
            set: { model.isShowingCreatePlan = $0 }
        )
    }

    private var isShowingTagPickerBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingTagPicker },
            set: { model.isShowingTagPicker = $0 }
        )
    }

    private var isShowingCurrencyPickerBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingCurrencyPicker },
            set: { model.isShowingCurrencyPicker = $0 }
        )
    }

    private var selectedCurrencyBinding: Binding<Currency?> {
        Binding(
            get: { model.selectedCurrency },
            set: { newValue in
                if let newValue { model.selectedCurrency = newValue }
            }
        )
    }

    private var isShowingLocationPickerBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingLocationPicker },
            set: { model.isShowingLocationPicker = $0 }
        )
    }

    private var selectedTagBinding: Binding<Components.Schemas.ListingTag> {
        Binding(
            get: { model.selectedTag },
            set: { model.selectedTag = $0 }
        )
    }

    private var canSubmitListing: Bool {
        !model.planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.stateId != nil
            && model.countryId != nil
    }

    // MARK: - Subviews

    private var editableSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            editableRow(label: "Trip name") {
                TextField("Trip name", text: planNameBinding)
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundStyle(Constants.ContentB)
                    .multilineTextAlignment(.trailing)
            }

            divider

            editableRow(label: "Duration") {
                // Pluralized in the String Catalog by the count argument.
                Text("\(model.durationDays) days")
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundStyle(Constants.ContentB)
                    .multilineTextAlignment(.trailing)
            }

            divider

            editableRow(label: "Location") {
                Button {
                    model.isShowingLocationPicker = true
                } label: {
                    Text(model.locationName.isEmpty ? "—" : model.locationName)
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .foregroundStyle(Constants.ContentB)
                        .multilineTextAlignment(.trailing)
                }
                .buttonStyle(.plain)
            }

            divider

            editableRow(label: "Budget per person") {
                TextField("0", text: priceTextBinding)
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundStyle(Constants.ContentB)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .onChange(of: model.priceText) { _, newValue in
                        let formatted = model.formatPrice(newValue)
                        if formatted != newValue {
                            model.priceText = formatted
                        }
                    }
            }

            divider

            editableRow(label: "Tag") {
                Button {
                    model.isShowingTagPicker = true
                } label: {
                    ListingTag(tag: model.selectedTag)
                }
                .buttonStyle(.plain)
            }

            divider

            editableRow(label: "Currency") {
                Button {
                    model.isShowingCurrencyPicker = true
                } label: {
                    Text("\(model.selectedCurrency.rawValue) (\(model.selectedCurrency.symbol))")
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .foregroundStyle(Constants.ContentB)
                        .multilineTextAlignment(.trailing)
                }
                .buttonStyle(.plain)
            }

            divider
        }
    }

    private func editableRow<Content: View>(
        label: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .leading)

            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Constants.DividerStroke)
            .frame(height: 1)
    }

    private var planDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentM)

            TextField(
                "Describe your plan...",
                text: descriptionTextBinding,
                axis: .vertical
            )
            .font(Font.custom("Be Vietnam Pro", size: 16))
            .foregroundStyle(Constants.ContentB)
            .lineLimit(3...6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 435, height: 455)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        UploadTripFormView(
            mode: .create(service: TripDetailService(), tripId: nil),
            onClose: {},
            onPublishSuccess: { _ in }
        )
    }
}
