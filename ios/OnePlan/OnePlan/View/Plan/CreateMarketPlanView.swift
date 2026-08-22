//
//  CreateMarketPlanView.swift
//  OnePlan
//
//  Created by Codex on 27/3/26.
//

import PhotosUI
import SwiftUI

struct CreateMarketPlanView: View {
    private enum Field: Hashable {
        case planName
        case message
    }

    @Binding var allPlanItems: [PlanItemDto]
    @Binding var editingPlanItem: PlanItemDto?
    @Binding var isPresented: Bool
    @Binding var planItemImagesById: [Int: [UIImage]]

    @State private var planName: String
    @State private var message: String
    @State private var selectedDayIndex: Int
    @State private var startTime: Date
    @State private var locationText: String
    @State private var selectedLatitude: Double?
    @State private var selectedLongitude: Double?
    @State private var selectedAddress: String?
    @State private var selectedImages: [UIImage] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingRemotePhotos = false

    // Overlays
    @State private var showTimePicker = false
    @State private var isLocationSheetPresented = false
    @State private var selectedCategory: String?
    @State private var isShowingDeleteAlert = false
    @FocusState private var focusedField: Field?

    let days: [String]
    let maxMessageCount: Int
    let tripId: Int
    let planItemImageUrlsById: [Int: [String]]

    // NOTE: This view dismisses via the `isPresented` binding, never the
    // `\.dismiss` action. Reading `@Environment(\.dismiss)` here is therefore
    // dead — and on iOS < 26 it's actively harmful: as a pushed destination it
    // would feed the action-env NavigationStack relayout loop (the "New Plan"
    // freeze). Intentionally NOT read. See LiquidGlassCompat.StableDismiss.

    private var isEditing: Bool { editingPlanItem != nil }

    init(
        allPlanItems: Binding<[PlanItemDto]>,
        editingPlanItem: Binding<PlanItemDto?>,
        isPresented: Binding<Bool>,
        planItemImagesById: Binding<[Int: [UIImage]]>,
        planName: String = "",
        message: String = "",
        selectedDayIndex: Int = 0,
        days: [String] = ["Day 1", "Day 2", "Day 3"],
        timeText: String = "08:00",
        locationText: String = "",
        maxMessageCount: Int = 200,
        images: [UIImage] = [],
        planItemImageUrlsById: [Int: [String]] = [:],
        tripId: Int = 0
    ) {
        self._allPlanItems = allPlanItems
        self._editingPlanItem = editingPlanItem
        self._isPresented = isPresented
        self._planItemImagesById = planItemImagesById
        self._planName = State(initialValue: planName)
        self._message = State(initialValue: message)
        self._selectedDayIndex = State(initialValue: selectedDayIndex)
        self._locationText = State(initialValue: locationText)
        if let editingItem = editingPlanItem.wrappedValue {
            self._selectedLatitude = State(initialValue: editingItem.latitude)
            self._selectedLongitude = State(initialValue: editingItem.longitude)
            self._selectedAddress = State(initialValue: editingItem.address)
        }
        if let editingItem = editingPlanItem.wrappedValue,
           let storedImages = planItemImagesById.wrappedValue[editingItem.id] {
            self._selectedImages = State(initialValue: storedImages)
        } else {
            self._selectedImages = State(initialValue: images)
        }
        self.days = days
        self.maxMessageCount = maxMessageCount
        self.tripId = tripId
        self.planItemImageUrlsById = planItemImageUrlsById

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        if let parsed = timeFormatter.date(from: timeText) {
            self._startTime = State(initialValue: parsed)
        } else {
            var components = DateComponents()
            components.hour = 8
            components.minute = 0
            self._startTime = State(
                initialValue: Calendar.current.date(from: components) ?? Date()
            )
        }
    }

    private var formattedTime: String {
        DisplayFormatters.time(startTime)  // DISPLAY only — locale-dependent
    }

    /// Canonical POSIX "HH:mm" used for the stored/wire `startTime`. Never store
    /// `formattedTime` (its 12h/24h + AM-PM symbols are locale-dependent and
    /// break both `MarketPlanSection.parseHourMinute` and the server's HH:MM
    /// contract). Mirrors the trip-side PlanFormModel serialization.
    private static let wireTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var wireTime: String {
        Self.wireTimeFormatter.string(from: startTime)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                planNameSection

                formSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: "Save plan") {
                dismissKeyboard()
                saveItem()
            }
            .disabled(planName.isEmpty)
            .opacity(planName.isEmpty ? 0.5 : 1)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Constants.Background)
        }
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissKeyboard()
                        isShowingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Constants.Warning500)
                    }
                }
            }
        }
        .alert("Delete this plan?", isPresented: $isShowingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let item = editingPlanItem {
                    allPlanItems.removeAll { $0.id == item.id }
                    planItemImagesById.removeValue(forKey: item.id)
                }
                editingPlanItem = nil
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(planName)\"?")
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
        .fullScreenCover(isPresented: $isLocationSheetPresented) {
            LocationDetailView(
                initialLocationName: "",
                initialLocationAddress: "",
                initialLatitude: 0,
                initialLongitude: 0,
                onDismiss: { isLocationSheetPresented = false },
                pickerConfig: LocationPickerConfig(
                    onLocationSelected: { item in
                        selectedCategory = item.category
                        locationText = item.title
                        selectedLatitude = item.latitude
                        selectedLongitude = item.longitude
                        selectedAddress = item.address.isEmpty ? nil : item.address
                        isLocationSheetPresented = false
                    },
                    onPinsAddedToTrip: {
                        editingPlanItem = nil
                        isPresented = false
                    },
                    onBoardPinsSelected: { pins in
                        appendBoardPins(pins)
                    }
                )
            )
        }
        .overlay {
            if showTimePicker {
                BottomSheet(
                    isPresented: $showTimePicker,
                    sheetHeight: 300,
                    backdropOpacity: 0.15
                ) { dismissSheet in
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 35, height: 4.9)
                            .padding(.top, 12)

                        Text("Select Time")
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundStyle(Constants.ContentB)
                            .padding(.top, 16)

                        DatePicker(
                            "",
                            selection: $startTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(height: 180)

                        Button {
                            dismissSheet()
                        } label: {
                            Text("Done")
                                .font(
                                    Font.beVietnamPro(16, weight: .medium)
                                )
                                .foregroundStyle(Constants.White)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Constants.BlueBase)
                                .cornerRadius(22)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .onChange(of: photoPickerItems) { _, newItems in
            Task {
                for item in newItems {
                    if selectedImages.count >= 5 { break }
                    if let data = try? await item.loadTransferable(
                        type: Data.self
                    ),
                        let image = UIImage(data: data)
                    {
                        selectedImages.append(image)
                    }
                }
                photoPickerItems = []
            }
        }
        .task(id: editingPlanItem?.id) {
            await loadRemoteImagesForEditingIfNeeded()
        }
    }

    // MARK: - Subviews

    private var planNameSection: some View {
        VStack(spacing: 8) {
            Text("Plan name")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentB)

            TextField(
                "",
                text: $planName,
                prompt: Text("Enter name")
                    .font(Font.custom("Be Vietnam Pro", size: 36))
                    .foregroundStyle(Constants.ContentB.opacity(0.2))
            )
            .font(Font.custom("Be Vietnam Pro", size: 36))
            .foregroundStyle(Constants.ContentB)
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: .planName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            daySelector

            // Time
            Button {
                dismissKeyboard()
                showTimePicker.toggle()
            } label: {
                detailRow(
                    title: "Time",
                    value: formattedTime,
                    valueColor: Constants.ContentB,
                    valueWeight: .regular
                )
            }
            .buttonStyle(.plain)

            // Location
            Button {
                dismissKeyboard()
                isLocationSheetPresented = true
            } label: {
                detailRow(
                    title: "Location",
                    value: locationText.isEmpty ? String(localized: "Choose") : locationText,
                    valueColor: locationText.isEmpty
                        ? Constants.ContentL : Constants.ContentB,
                    valueWeight: locationText.isEmpty ? .light : .regular
                )
            }
            .buttonStyle(.plain)

            messageSection

            photoSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    Button {
                        selectedDayIndex = index
                    } label: {
                        Text(day)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(
                                index == selectedDayIndex
                                    ? Constants.White : Constants.ContentB
                            )
                            .frame(width: 80, height: 35)
                            .background(
                                Capsule()
                                    .fill(
                                        index == selectedDayIndex
                                            ? Constants.BlueBase
                                            : Constants.Surface
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detailRow(
        title: LocalizedStringKey,
        value: String,
        valueColor: Color,
        valueWeight: Font.Weight
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)

            Spacer(minLength: 8)

            Text(value)
                .font(
                    Font.beVietnamPro(16, weight: valueWeight)
                )
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Constants.Surface)
        .cornerRadius(16)
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .focused($focusedField, equals: .message)
                    .scrollContentBackground(.hidden)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 95,
                        maxHeight: 95,
                        alignment: .topLeading
                    )
                    .onChange(of: message) { _, newValue in
                        if newValue.count > maxMessageCount {
                            message = String(newValue.prefix(maxMessageCount))
                        }
                    }

                if message.isEmpty {
                    Text("Description")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentL)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }

            Text("\(message.count)/\(maxMessageCount)")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentL)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Constants.Surface)
        .cornerRadius(16)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Photos (\(selectedImages.count)/5)")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)

                if isLoadingRemotePhotos {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Constants.ContentM)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if selectedImages.count < 5 {
                        PhotosPicker(
                            selection: $photoPickerItems,
                            maxSelectionCount: 5 - selectedImages.count,
                            matching: .images
                        ) {
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                            .fill(Constants.Neutral100)
                            .frame(width: 112, height: 112)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundStyle(Constants.ContentB)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(Array(selectedImages.enumerated()), id: \.offset) {
                        index,
                        image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 112, height: 112)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                )

                            Button {
                                selectedImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Constants.White)
                                    .shadow(radius: 2)
                            }
                            .offset(x: -4, y: 4)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.Surface)
        .cornerRadius(16)
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 385, height: 385)
            .blur(radius: 60)
            .offset(y: -280)
            .allowsHitTesting(false)
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    // MARK: - Save Logic

    @MainActor
    private func loadRemoteImagesForEditingIfNeeded() async {
        guard selectedImages.isEmpty else { return }
        guard let editingItem = editingPlanItem else { return }
        guard let remoteUrls = planItemImageUrlsById[editingItem.id],
              !remoteUrls.isEmpty else { return }

        isLoadingRemotePhotos = true
        defer { isLoadingRemotePhotos = false }

        var loadedImages: [UIImage] = []
        loadedImages.reserveCapacity(min(remoteUrls.count, 5))

        for rawUrl in remoteUrls.prefix(5) {
            guard let url = URL(string: rawUrl) else { continue }
            guard let image = await TripImageCache.shared.image(
                for: url,
                maxPixelSize: 1200
            ) else { continue }
            loadedImages.append(image)
        }

        guard !Task.isCancelled else { return }
        guard !loadedImages.isEmpty else { return }

        selectedImages = loadedImages
        planItemImagesById[editingItem.id] = loadedImages
    }

    /// Appends board pins to the in-memory marketplace draft (`allPlanItems`),
    /// mapped onto the form's currently-selected day with staggered start times.
    /// Dismissal is handled by `onPinsAddedToTrip` (via ChooseLocationView's
    /// `onCompleted`), mirroring PlanFormView — so this only mutates the draft.
    private func appendBoardPins(_ pins: [BoardPinDto]) {
        guard !pins.isEmpty else { return }
        let safeDayNumber = min(max(selectedDayIndex + 1, 1), max(days.count, 1))
        let planDate = MarketplaceEditorDayMapper.planDate(forDayNumber: safeDayNumber)
        var nextId = (allPlanItems.map(\.id).max() ?? 0) + 1
        let baseSortOrder = allPlanItems.filter { $0.planDate == planDate }.count
        let createdAt = ISO8601DateFormatter().string(from: Date())

        for (offset, pin) in pins.enumerated() {
            // Stagger 30 min from 09:00, clamped to 23:30 (mirrors the trip path).
            let totalMinutes = min(9 * 60 + offset * 30, 23 * 60 + 30)
            let startTime = String(
                format: "%02d:%02d",
                totalMinutes / 60,
                totalMinutes % 60
            )
            let newItem = PlanItemDto(
                id: nextId,
                tripId: tripId,
                planDate: planDate,
                title: pin.name,
                description: pin.notes,
                location: pin.address,
                latitude: pin.latitude,
                longitude: pin.longitude,
                address: pin.address,
                startTime: startTime,
                category: nil,
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: nil,
                sortOrder: baseSortOrder + offset,
                createdAt: createdAt,
                members: []
            )
            allPlanItems.append(newItem)
            nextId += 1
        }
    }

    private func saveItem() {
        let safeDayNumber = min(max(selectedDayIndex + 1, 1), max(days.count, 1))
        let planDate = MarketplaceEditorDayMapper.planDate(forDayNumber: safeDayNumber)
        let locationToSave = locationText.isEmpty ? nil : locationText
        let latitudeToSave: Double? = locationToSave == nil ? nil : selectedLatitude
        let longitudeToSave: Double? = locationToSave == nil ? nil : selectedLongitude
        let addressToSave: String? = locationToSave == nil ? nil : selectedAddress

        if let editing = editingPlanItem,
            let index = allPlanItems.firstIndex(where: { $0.id == editing.id })
        {
            var updated = editing
            updated.planDate = planDate
            updated.title = planName
            updated.description = message.isEmpty ? nil : message
            updated.location = locationToSave
            updated.latitude = latitudeToSave
            updated.longitude = longitudeToSave
            updated.address = addressToSave
            updated.startTime = wireTime
            allPlanItems[index] = updated
            if selectedImages.isEmpty {
                planItemImagesById.removeValue(forKey: updated.id)
            } else {
                planItemImagesById[updated.id] = selectedImages
            }
        } else {
            let maxId = allPlanItems.map(\.id).max() ?? 0
            let sortOrder = allPlanItems.filter { $0.planDate == planDate }
                .count
            let newItem = PlanItemDto(
                id: maxId + 1,
                tripId: tripId,
                planDate: planDate,
                title: planName,
                description: message.isEmpty ? nil : message,
                location: locationToSave,
                latitude: latitudeToSave,
                longitude: longitudeToSave,
                address: addressToSave,
                startTime: wireTime,
                category: nil,
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: nil,
                sortOrder: sortOrder,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                members: []
            )
            allPlanItems.append(newItem)
            if !selectedImages.isEmpty {
                planItemImagesById[newItem.id] = selectedImages
            }
        }
        editingPlanItem = nil
        isPresented = false
    }
}

#Preview {
    @Previewable @State var items: [PlanItemDto] = []
    @Previewable @State var editing: PlanItemDto? = nil
    @Previewable @State var isPresented = true

    NavigationStack {
        CreateMarketPlanView(
            allPlanItems: $items,
            editingPlanItem: $editing,
            isPresented: $isPresented,
            planItemImagesById: .constant([:])
        )
    }
}
