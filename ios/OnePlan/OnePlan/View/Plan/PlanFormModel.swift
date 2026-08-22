//
//  PlanFormModel.swift
//  OnePlan
//

import Foundation

@Observable
@MainActor
final class PlanFormModel {
    enum Mode: Equatable {
        case create
        case edit(PlanItemDto)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create): return true
            case (.edit(let a), .edit(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    enum SubmitError: Error {
        case missingTitle
        case beforeTripStart(tripStartDate: Date)
        case voiceUploadFailed
        case serverFailed(message: String)
    }

    // MARK: - Constants

    static let maxDays = 14

    // MARK: - Immutable context

    let mode: Mode
    let tripId: Int
    let members: [TripMemberDto]
    let isPlanningMode: Bool
    let tripStartDate: Date?
    let service: TripDetailService

    // MARK: - Computed day list (reads from service)

    var availableDayNumbers: [Int] {
        service.availablePlanningDays()
    }

    // MARK: - Mutable form fields

    var planName: String = ""
    var selectedPlanDate: Date = Date()
    var selectedDayNumber: Int = 1
    var startTime: Date = PlanFormModel.defaultStartTime
    var locationText: String = ""
    var selectedLatitude: Double?
    var selectedLongitude: Double?
    var selectedAddress: String?
    var selectedCategory: String?
    var descriptionText: String = ""

    var isAllSelected: Bool = true
    var selectedMemberIds: Set<Int> = []

    var existingVoiceUrl: String?
    var existingVoiceDuration: Int?

    // MARK: - Derived

    var isEditMode: Bool {
        if case .edit = mode { return true } else { return false }
    }

    var acceptedMembers: [TripMemberDto] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }
    }

    var acceptedMemberIds: [Int] {
        acceptedMembers.map { Int($0.userId) }
    }

    var isBeforeTripStartDate: Bool {
        guard !isPlanningMode, let tripStartDate else { return false }
        return Calendar.current.startOfDay(for: selectedPlanDate)
            < Calendar.current.startOfDay(for: tripStartDate)
    }

    var canSubmit: Bool {
        let trimmed = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if !isPlanningMode && isBeforeTripStartDate { return false }
        return true
    }

    // MARK: - Init

    init(
        mode: Mode,
        tripId: Int,
        members: [TripMemberDto],
        isPlanningMode: Bool,
        service: TripDetailService,
        tripStartDate: Date?,
        initialPlanDate: String? = nil,
        initialDayNumber: Int? = nil
    ) {
        self.mode = mode
        self.tripId = tripId
        self.members = members
        self.isPlanningMode = isPlanningMode
        self.service = service
        self.tripStartDate = tripStartDate

        switch mode {
        case .create:
            hydrateForCreate(
                initialPlanDate: initialPlanDate,
                initialDayNumber: initialDayNumber
            )
        case .edit(let item):
            hydrateForEdit(item, initialDayNumber: initialDayNumber)
        }

        clampPlanDateToTripStartIfNeeded()
    }

    private func hydrateForCreate(initialPlanDate: String?, initialDayNumber: Int?) {
        if let dayNumber = initialDayNumber {
            selectedDayNumber = dayNumber
        } else {
            selectedDayNumber = availableDayNumbers.first ?? 1
        }

        if let initialPlanDate, !initialPlanDate.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsed = formatter.date(from: initialPlanDate) {
                selectedPlanDate = parsed
            }
        }
    }

    private func hydrateForEdit(_ item: PlanItemDto, initialDayNumber: Int?) {
        planName = item.title
        descriptionText = item.description ?? ""
        locationText = item.location ?? ""
        selectedLatitude = item.latitude
        selectedLongitude = item.longitude
        selectedAddress = item.address
        existingVoiceUrl = item.voiceUrl
        existingVoiceDuration = item.voiceDuration.map { Int($0) }
        selectedCategory = item.category.flatMap { $0.value1.rawValue }

        if let dayNumber = initialDayNumber ?? item.dayNumber.map({ Int($0) }) {
            selectedDayNumber = dayNumber
        }

        if let planDate = item.planDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsed = formatter.date(from: planDate) {
                selectedPlanDate = parsed
            }
        }

        if let startTimeStr = item.startTime,
           !startTimeStr.trimmingCharacters(in: .whitespaces).isEmpty
        {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            if let parsed = formatter.date(from: startTimeStr) {
                startTime = parsed
            }
        }

        // Lenient "All" detection: if the item covers every accepted member (or more),
        // treat it as "All" rather than a subset.
        let acceptedIds = Set(acceptedMemberIds)
        let itemMemberIds = Set(item.members.map { Int($0.userId) })
        if itemMemberIds == acceptedIds || itemMemberIds.count >= acceptedIds.count {
            isAllSelected = true
            selectedMemberIds = []
        } else {
            isAllSelected = false
            selectedMemberIds = itemMemberIds
        }
    }

    // MARK: - Mutations

    var canAddDay: Bool {
        service.availablePlanningDays().count < Self.maxDays
    }

    func addDay() {
        guard canAddDay else { return }
        service.addPlanningDay()
        selectedDayNumber = service.availablePlanningDays().last ?? 1
    }

    /// Can delete any day as long as there's more than one day.
    func canDeleteDay(_ day: Int) -> Bool {
        let count = service.availablePlanningDays().count
        return count > 1 && day >= 1 && day <= count
    }

    /// Deletes a day and shifts all subsequent plans down by one day number.
    func deleteDay(_ day: Int) {
        guard canDeleteDay(day) else { return }

        // Adjust selected day before deletion
        let oldSelectedDay = selectedDayNumber

        // Delete via service (handles plan renumbering)
        service.deletePlanningDay(day)

        // Adjust selected day
        if oldSelectedDay == day {
            selectedDayNumber = max(day - 1, 1)
        } else if oldSelectedDay > day {
            selectedDayNumber = oldSelectedDay - 1
        }
    }

    func selectAllMembers() {
        isAllSelected = true
        selectedMemberIds.removeAll()
    }

    func toggleMember(_ memberId: Int) {
        if isAllSelected {
            isAllSelected = false
        }
        if selectedMemberIds.contains(memberId) {
            selectedMemberIds.remove(memberId)
            if selectedMemberIds.isEmpty {
                isAllSelected = true
            }
        } else {
            selectedMemberIds.insert(memberId)
        }
    }

    func applyLocationSelection(
        title: String,
        category: String?,
        latitude: Double?,
        longitude: Double?,
        address: String?
    ) {
        locationText = title
        selectedCategory = category
        selectedLatitude = latitude
        selectedLongitude = longitude
        selectedAddress = address
    }

    func deleteExistingVoice() {
        existingVoiceUrl = nil
        existingVoiceDuration = nil
    }

    func clampPlanDateToTripStartIfNeeded() {
        guard let tripStartDate else { return }
        let calendar = Calendar.current
        let startOfTrip = calendar.startOfDay(for: tripStartDate)
        let startOfSelected = calendar.startOfDay(for: selectedPlanDate)
        if startOfSelected < startOfTrip {
            selectedPlanDate = startOfTrip
        }
    }

    // MARK: - Submit

    func submit(
        service: TripDetailService,
        uploadService: StorageUploadService,
        audioManager: AudioRecordingManager
    ) async -> Result<Void, SubmitError> {
        let trimmedName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(.missingTitle)
        }

        if !isPlanningMode, isBeforeTripStartDate, let tripStartDate {
            return .failure(.beforeTripStart(tripStartDate: tripStartDate))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let planDateString: String? = isPlanningMode ? nil : dateFormatter.string(from: selectedPlanDate)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: startTime)

        let allMemberIds = acceptedMemberIds
        let userIds: [Int] = isAllSelected
            ? allMemberIds
            : allMemberIds.filter { selectedMemberIds.contains($0) }

        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLoc = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dayNum: Int? = isPlanningMode ? selectedDayNumber : nil

        // Clearing the note on edit must send "" (sentinel), not nil: the OpenAPI
        // encoder omits nil keys entirely, and the server treats an absent key as
        // "no change" — so the old note would stick. Mirrors the voiceUrl clear flow.
        let descriptionToSend: String? = trimmedDesc.isEmpty
            ? (isEditMode ? "" : nil)
            : trimmedDesc

        // Resolve voice: upload new → sentinel for cleared → reuse existing → none.
        var voiceUrl: String? = nil
        var voiceDur: Int? = nil

        if let audioData = audioManager.audioData() {
            do {
                voiceUrl = try await uploadService.uploadAudio(audioData, tripId: tripId)
                voiceDur = audioManager.durationSeconds
            } catch {
                return .failure(.voiceUploadFailed)
            }
        } else if isEditMode, case .edit(let originalItem) = mode {
            if existingVoiceUrl == nil, originalItem.voiceUrl != nil {
                // User deleted existing voice — empty string signals clear to the server.
                voiceUrl = ""
            } else {
                voiceUrl = existingVoiceUrl
                voiceDur = existingVoiceDuration
            }
        }

        let locationToSend = trimmedLoc.isEmpty ? nil : trimmedLoc
        // Coordinates are only set via POI picker, so they stay coherent with locationText.
        // If locationText is cleared, drop coords too.
        let latitudeToSend: Double? = locationToSend == nil ? nil : selectedLatitude
        let longitudeToSend: Double? = locationToSend == nil ? nil : selectedLongitude
        let addressToSend: String? = locationToSend == nil ? nil : selectedAddress

        switch mode {
        case .create:
            let result = await service.createPlanItem(
                tripId: tripId,
                title: trimmedName,
                planDate: planDateString,
                description: descriptionToSend,
                location: locationToSend,
                latitude: latitudeToSend,
                longitude: longitudeToSend,
                address: addressToSend,
                startTime: timeString,
                category: selectedCategory,
                userIds: userIds,
                voiceUrl: voiceUrl,
                voiceDuration: voiceDur,
                dayNumber: dayNum
            )
            switch result {
            case .success:
                return .success(())
            case .failure(let error):
                return .failure(.serverFailed(message: error.localizedDescription))
            }

        case .edit(let item):
            let result = await service.updatePlanItem(
                tripId: tripId,
                planItemId: Int(item.id),
                title: trimmedName,
                planDate: planDateString,
                description: descriptionToSend,
                location: locationToSend,
                latitude: latitudeToSend,
                longitude: longitudeToSend,
                address: addressToSend,
                startTime: timeString,
                category: selectedCategory,
                userIds: userIds,
                voiceUrl: voiceUrl,
                voiceDuration: voiceDur,
                dayNumber: dayNum
            )
            switch result {
            case .success:
                return .success(())
            case .failure(let error):
                return .failure(.serverFailed(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Helpers

    static var defaultStartTime: Date {
        var components = DateComponents()
        components.hour = 8
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}
