//
//  PlanFormView.swift
//  OnePlan
//

import SwiftUI

struct PlanFormView: View {
    @State private var form: PlanFormModel
    @State private var audioManager = AudioRecordingManager()
    @State private var uploadService = StorageUploadService()
    let service: TripDetailService

    // See StableDismiss: avoids the iOS-<26 NavigationStack relayout re-render loop
    // that froze the app when this view was pushed from the trip plan tab.
    @State private var stableDismiss = StableDismiss()

    // Transient view-only state (not part of form data)
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var isLocationSheetPresented = false
    @State private var isRecordingModalPresented = false
    @State private var showDeleteRecordingAlert = false
    @State private var isSubmitting = false
    @State private var errorAlertMessage: String?
    @State private var dayToDelete: Int?

    init(form: PlanFormModel, service: TripDetailService) {
        _form = State(initialValue: form)
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                planNameHeader

                VStack(alignment: .leading, spacing: 4) {
                    scopeRow
                        .padding(.horizontal)

                    timeRow
                        .padding(.horizontal)

                    locationRow
                        .padding(.horizontal)

                    whoJoinSection
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    messageSection
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if !form.isEditMode {
                    submitButton
                        .padding(.horizontal)
                        .padding(.top, 12)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            if form.isEditMode {
                ToolbarItem(placement: .topBarTrailing) {
                    editCheckmarkButton
                }
                .sharedBackgroundHiddenCompat()
            }
        }
        .blur(radius: isRecordingModalPresented ? 4 : 0)
        .allowsHitTesting(!isRecordingModalPresented)
        .overlay {
            if isRecordingModalPresented {
                RecordingModalOverlay(
                    planName: form.planName.isEmpty ? defaultRecordingTitle : form.planName,
                    audioManager: audioManager,
                    onClose: {
                        dismissRecordingModal()
                    },
                    onStop: {
                        dismissRecordingModal()
                    }
                )
                .onChange(of: audioManager.isRecording) { _, isRecording in
                    guard !isRecording else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRecordingModalPresented = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .fullScreenCover(isPresented: $isLocationSheetPresented) {
            LocationDetailView(
                initialLocationName: "",
                initialLocationAddress: "",
                initialLatitude: 0,
                initialLongitude: 0,
                onDismiss: { isLocationSheetPresented = false },
                pickerConfig: LocationPickerConfig(
                    tripId: form.tripId,
                    dayNumber: form.isPlanningMode ? form.selectedDayNumber : nil,
                    planDate: form.isPlanningMode ? nil : planDateForSelectedDay,
                    onLocationSelected: { item in
                        form.applyLocationSelection(
                            title: item.title,
                            category: item.category,
                            latitude: item.latitude,
                            longitude: item.longitude,
                            address: item.address.isEmpty ? nil : item.address
                        )
                        isLocationSheetPresented = false
                    },
                    onPinsAddedToTrip: {
                        stableDismiss()
                    }
                )
            )
        }
        .overlay {
            if showDatePicker {
                datePickerSheet
            } else if showTimePicker {
                timePickerSheet
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .captureStableDismiss(stableDismiss)
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorAlertMessage != nil },
                set: { if !$0 { errorAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorAlertMessage = nil }
        } message: {
            Text(errorAlertMessage ?? "Something went wrong")
        }
        .alert("Delete recording?", isPresented: $showDeleteRecordingAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                audioManager.resetRecording()
                form.deleteExistingVoice()
            }
        } message: {
            Text("The voice recording will be removed from this plan.")
        }
        .alert(
            "Delete Day \(dayToDelete ?? 0)?",
            isPresented: Binding(
                get: { dayToDelete != nil },
                set: { if !$0 { dayToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { dayToDelete = nil }
            Button("Delete", role: .destructive) {
                if let day = dayToDelete {
                    form.deleteDay(day)
                }
                dayToDelete = nil
            }
        } message: {
            Text("All plans on Day \(dayToDelete ?? 0) will be deleted. Plans on later days will be moved up.")
        }
    }

    private var defaultRecordingTitle: String {
        form.isEditMode ? String(localized: "Edit Plan") : String(localized: "New Plan")
    }

    private func dismissRecordingModal() {
        audioManager.stopRecording()
        withAnimation(.easeInOut(duration: 0.2)) {
            isRecordingModalPresented = false
        }
    }

    // MARK: - Header

    private var planNameHeader: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Plan name")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .center)

            TextField("Enter name", text: $form.planName)
                .font(Font.custom("Be Vietnam Pro", size: 36))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Scope row (day chips vs date row)

    private var scopeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(form.availableDayNumbers, id: \.self) { day in
                        dayChip(for: day)
                            .onTapGesture {
                                selectDay(day)
                            }
                            .onLongPressGesture(minimumDuration: 0.1) {
                                if form.canDeleteDay(day) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    dayToDelete = day
                                }
                            }
                    }

                    if form.canAddDay {
                        Button {
                            form.addDay()
                        } label: {
                            Text("+ add")
                                .font(Font.beVietnamPro(15, weight: .medium))
                                .foregroundColor(Constants.ContentB)
                                .padding(.horizontal, 16)
                                .frame(height: 34)
                                .background(Constants.Surface)
                                .cornerRadius(17)
                                .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func dayChip(for day: Int) -> some View {
        let isSelected = form.selectedDayNumber == day
        let fg = isSelected ? Constants.White : Constants.ContentB
        let bg = isSelected ? Constants.BlueBase : Constants.Surface

        Group {
            if let date = dateForDay(day) {
                HStack(spacing: 6) {
                    Text(DisplayFormatters.monthDay(date))
                        .font(Font.beVietnamPro(13, weight: .medium))
                        .foregroundColor(isSelected ? Constants.White.opacity(0.75) : Constants.ContentM)
                    Text("Day \(day)")
                        .font(Font.beVietnamPro(15, weight: .semibold))
                        .foregroundColor(fg)
                }
            } else {
                Text("Day \(day)")
                    .font(Font.beVietnamPro(15, weight: .medium))
                    .foregroundColor(fg)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(bg)
        .cornerRadius(17)
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
    }

    private func dateForDay(_ day: Int) -> Date? {
        guard day >= 1, let start = form.tripStartDate else { return nil }
        return Calendar.current.date(
            byAdding: .day,
            value: day - 1,
            to: Calendar.current.startOfDay(for: start)
        )
    }

    private func selectDay(_ day: Int) {
        form.selectedDayNumber = day
        // In date-mode trips (ongoing), submission keys off `selectedPlanDate`
        // — keep it in sync so the chip tap actually changes the saved date.
        if !form.isPlanningMode, let date = dateForDay(day) {
            form.selectedPlanDate = date
        }
    }

    // MARK: - Time row

    private var timeRow: some View {
        Button {
            showTimePicker.toggle()
        } label: {
            PlanFormInfoRow(
                title: "Time",
                value: formattedTime,
                valueColor: Constants.ContentB,
                valueWeight: .regular
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Location row

    private var locationRow: some View {
        Button {
            isLocationSheetPresented = true
        } label: {
            PlanFormInfoRow(
                title: "Location",
                value: form.locationText.isEmpty ? String(localized: "Choose") : form.locationText,
                valueColor: form.locationText.isEmpty ? Constants.ContentL : Constants.ContentB,
                valueWeight: form.locationText.isEmpty ? .light : .regular
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Who Join

    private var whoJoinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who join")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    PlanFormMemberChip(
                        name: "All",
                        avatarUrl: nil,
                        isAllOption: true,
                        isSelected: form.isAllSelected
                    ) {
                        form.selectAllMembers()
                    }

                    ForEach(form.acceptedMembers, id: \.userId) { member in
                        let memberId = Int(member.userId)
                        PlanFormMemberChip(
                            name: member.displayName,
                            avatarUrl: member.avatarUrl,
                            isAllOption: false,
                            isSelected: form.selectedMemberIds.contains(memberId)
                        ) {
                            form.toggleMember(memberId)
                        }
                    }
                }
                .padding(.top, 4)
            }

            // One localizable sentence; the styled "Who join" run is inlined as
            // a %@ placeholder so translators control word order.
            Text("Members selected in \"\(Text("Who join").foregroundColor(Constants.ContentB))\" section will receive notifications as the plan approaches.")
                .foregroundColor(Constants.ContentM)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Message

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Message")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentM)

                Spacer(minLength: 8)

                RecordButton(
                    hasRecording: audioManager.recordedFileURL != nil || form.existingVoiceUrl != nil,
                    action: {
                        Task {
                            await audioManager.checkAuthorization()
                            if audioManager.isAuthorized {
                                audioManager.startRecording()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isRecordingModalPresented = true
                                }
                            }
                        }
                    },
                    onDelete: {
                        showDeleteRecordingAlert = true
                    }
                )
            }

            TextEditor(text: $form.descriptionText)
                .font(
                    Font.beVietnamPro(16, weight: .light)
                )
                .foregroundColor(Constants.ContentB)
                .scrollContentBackground(.hidden)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 95,
                    alignment: .topLeading
                )
                .onChange(of: form.descriptionText) { _, newValue in
                    if newValue.count > 500 {
                        form.descriptionText = String(newValue.prefix(500))
                    }
                }

            Text("\(form.descriptionText.count)/500")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentL)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Constants.White)
        .cornerRadius(20)
    }

    // MARK: - Primary actions

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Text(submitButtonTitle)
                .font(Font.beVietnamPro(16, weight: .medium))
                .foregroundColor(Constants.White)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(form.canSubmit && !isSubmitting ? Constants.BlueBase : Constants.ContentL)
                .cornerRadius(25)
        }
        .disabled(!form.canSubmit || isSubmitting || service.isCreatingPlanItem || service.isUpdatingPlanItem)
    }

    private var editCheckmarkButton: some View {
        Button {
            submit()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.ContentB)
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .glassEffectCompat()
        }
        .buttonStyle(.plain)
        .disabled(!form.canSubmit || isSubmitting || service.isUpdatingPlanItem)
    }

    private var submitButtonTitle: String {
        if isSubmitting {
            return String(localized: "Saving...")
        }
        return form.isEditMode ? String(localized: "Update Plan") : String(localized: "Save Plan")
    }

    // MARK: - Pickers

    private var datePickerSheet: some View {
        BottomSheet(
            isPresented: $showDatePicker,
            sheetHeight: 300,
            backdropOpacity: 0.15
        ) { dismissSheet in
            VStack(spacing: 0) {
                Capsule()
                    .fill(Constants.ContentL.opacity(0.55))
                    .frame(width: 35, height: 4.9)
                    .padding(.top, 12)

                Text("Select Date")
                    .font(Font.beVietnamPro(16, weight: .medium))
                    .foregroundColor(Constants.ContentB)
                    .padding(.top, 16)

                Group {
                    if let tripStartDate = form.tripStartDate {
                        DatePicker(
                            "",
                            selection: $form.selectedPlanDate,
                            in: tripStartDate...,
                            displayedComponents: .date
                        )
                    } else {
                        DatePicker(
                            "",
                            selection: $form.selectedPlanDate,
                            displayedComponents: .date
                        )
                    }
                }
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 180)

                Button {
                    dismissSheet()
                } label: {
                    Text("Done")
                        .font(Font.beVietnamPro(16, weight: .medium))
                        .foregroundColor(Constants.White)
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

    private var timePickerSheet: some View {
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
                    .font(Font.beVietnamPro(16, weight: .medium))
                    .foregroundColor(Constants.ContentB)
                    .padding(.top, 16)

                DatePicker(
                    "",
                    selection: $form.startTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 180)

                Button {
                    dismissSheet()
                } label: {
                    Text("Done")
                        .font(Font.beVietnamPro(16, weight: .medium))
                        .foregroundColor(Constants.White)
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

    // MARK: - Formatting

    private var formattedDate: String {
        DisplayFormatters.date(form.selectedPlanDate)
    }

    // DISPLAY only (the wire time is built separately in PlanFormModel.submit).
    private var formattedTime: String {
        DisplayFormatters.time(form.startTime)
    }

    private var formattedPlanDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: form.selectedPlanDate)
    }

    /// Derives the planDate from the currently-selected day chip + trip start
    /// date, so a freshly-added "Day N" (via `+ add`) — which only updates
    /// `selectedDayNumber`, not `selectedPlanDate` — still produces the right
    /// date for bulk pin creation. Falls back to the form's `selectedPlanDate`
    /// when the trip has no start date.
    private var planDateForSelectedDay: String {
        let date = dateForDay(form.selectedDayNumber) ?? form.selectedPlanDate
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Submit

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            let result = await form.submit(
                service: service,
                uploadService: uploadService,
                audioManager: audioManager
            )
            switch result {
            case .success:
                stableDismiss()
            case .failure(let error):
                errorAlertMessage = errorMessage(for: error)
            }
        }
    }

    private func errorMessage(for error: PlanFormModel.SubmitError) -> String {
        switch error {
        case .missingTitle:
            return String(localized: "Please enter a plan name.")
        case .beforeTripStart(let tripStartDate):
            return String(localized: "Plan date cannot be before trip start date (\(DisplayFormatters.date(tripStartDate))).", comment: "%@ = the trip's start date")
        case .voiceUploadFailed:
            return String(localized: "Voice upload failed. Please check your connection and try again.")
        case .serverFailed(let message):
            return message  // server-provided message — passed through, not localized
        }
    }
}

// MARK: - Shared date parsing helper (used by callers constructing PlanFormModel)

@MainActor
enum PlanFormDateParser {
    static func parseTripStartDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let parsed = dateOnly.date(from: trimmed) {
            return parsed
        }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoWithFractional.date(from: trimmed) {
            return parsed
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }
}

// MARK: - Private components

private struct PlanFormInfoRow: View {
    let title: LocalizedStringKey
    let value: String
    let valueColor: Color
    let valueWeight: Font.Weight

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)

            Spacer(minLength: 8)

            Text(value)
                .font(
                    Font.beVietnamPro(16, weight: valueWeight)
                )
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Constants.White)
        .cornerRadius(20)
    }
}

private struct PlanFormMemberChip: View {
    let name: String
    let avatarUrl: String?
    let isAllOption: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if isAllOption {
                        Circle()
                            .fill(Constants.Black)
                            .frame(width: 32, height: 32)

                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Constants.White)
                    } else if let avatarUrl, let url = URL(string: avatarUrl) {
                        CachedRemoteImage(
                            url: url,
                            targetSize: CGSize(width: 36, height: 36)
                        ) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image("avatarPlaceholder")
                                .resizable()
                                .scaledToFill()
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Image("avatarPlaceholder")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    }
                }
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Constants.BlueBase : Color.clear,
                            lineWidth: 2
                        )
                }

                Text(name)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(
                        isSelected ? Constants.BlueBase : Constants.ContentM
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 54)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Create — Planning") {
    let previewService = TripDetailService()
    return NavigationStack {
        PlanFormView(
            form: PlanFormModel(
                mode: .create,
                tripId: 1,
                members: [],
                isPlanningMode: true,
                service: previewService,
                tripStartDate: nil,
                initialDayNumber: 1
            ),
            service: previewService
        )
    }
    .background(Constants.Background.ignoresSafeArea())
}
