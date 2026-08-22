//
//  BoardDetailView.swift
//  OnePlan
//
//  Created by ken on 11/5/26.
//

import SwiftUI

extension BoardPinDto: @retroactive Identifiable {}

struct BoardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var board: BoardSummaryDto

    init(board: BoardSummaryDto) {
        _board = State(initialValue: board)
    }

    @State private var detail: BoardDto?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isShowingDeleteBoardConfirm = false
    @State private var isDeletingBoard = false
    @State private var deleteBoardErrorMessage: String?
    @State private var isEditingBoard = false
    @State private var selectedPin: BoardPinDto?
    @State private var boardService = BoardService.shared

    @Environment(UserProfileService.self) private var userProfileService
    @State private var tripService = TripService()
    @State private var tripDetailService = TripDetailService()

    @State private var pendingPlanLocation: PendingPlanLocation?
    @State private var isAddingPinToTrip = false
    @State private var addToTripOutcome: AddToTripOutcome?
    @State private var addToTripErrorMessage: String?

    @State private var isShowingGenerateTrip = false
    @State private var isShowingLocationRequiredAlert = false
    // Set by the generate sheet on success; consumed in the sheet's onDismiss so
    // the new trip is opened only after the sheet is fully gone (avoids a sheet
    // dismiss racing the tab switch).
    @State private var generatedTrip: TripDto?

    private var pins: [BoardPinDto] { detail?.pins ?? [] }
    private var coverImageUrl: String? {
        detail?.coverImageUrl ?? board.coverImageUrl
    }
    private var locationLabel: String? {
        detail?.locationLabel ?? board.locationLabel
    }
    private var descriptionText: String? {
        detail?.description ?? board.description
    }
    // A trip can only be generated from a board that has a location — the
    // generated trip's destination is derived from it. Require at least a
    // country (state/city are optional in the location hierarchy).
    private var boardHasLocation: Bool {
        (detail?.countryId ?? board.countryId) != nil
    }

    private var tripOptions: [AddingPinTripOption] {
        (tripService.ongoingTrips + tripService.planningTrips).map { trip in
            AddingPinTripOption(
                id: String(trip.id),
                title: trip.name,
                status: trip.status.value1 == .ONGOING ? "Ongoing" : "Planning",
                imageName: "addingPinSingapore"
            )
        }
    }

    var body: some View {
        List {
            Section {
                BoardPinCountHeader(pinCount: pins.count)
                    .listRowInsets(
                        EdgeInsets(top: 24, leading: 0, bottom: 22, trailing: 0)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                Button {
                    isEditingBoard = true
                } label: {
                    boardSummary
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit this board")
                .listRowInsets(
                    EdgeInsets(
                        top: 0,
                        leading: 16,
                        bottom: 18,
                        trailing: 16
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if !pins.isEmpty {
                    Button {
                        if boardHasLocation {
                            isShowingGenerateTrip = true
                        } else {
                            isShowingLocationRequiredAlert = true
                        }
                    } label: {
                        generateTripLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Create a trip from these pins")
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: 16,
                            bottom: 18,
                            trailing: 16
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(pins, id: \.id) { pin in
                    Button {
                        guard pin.latitude != nil, pin.longitude != nil else {
                            return
                        }
                        selectedPin = pin
                    } label: {
                        BoardPinRow(pin: pin)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel(
                        "\(pin.name), \(pin.address ?? pin.notes ?? "")"
                    )
                }
                .onDelete(perform: deletePins)
            }
        }
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Constants.Background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIconButton(
                    systemName: "trash",
                    foregroundColor: Constants.Warning500,
                    horizontalPadding: 13
                ) {
                    isShowingDeleteBoardConfirm = true
                }
                .disabled(isDeletingBoard)
            }.sharedBackgroundHiddenCompat()
        }
        .alert("Delete board?", isPresented: $isShowingDeleteBoardConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard !isDeletingBoard else { return }
                Task { await performDelete() }
            }
        } message: {
            Text(
                "This will permanently delete this board and all of its pins. This action cannot be undone."
            )
        }
        .alert(
            "Failed to delete board",
            isPresented: Binding(
                get: { deleteBoardErrorMessage != nil },
                set: { if !$0 { deleteBoardErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deleteBoardErrorMessage = nil }
        } message: {
            Text(deleteBoardErrorMessage ?? "")
        }
        .alert(
            "Add a location first",
            isPresented: $isShowingLocationRequiredAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This board needs a location before you can generate a trip. Tap the board to edit it and add one.")
        }
        .sheet(
            isPresented: $isShowingGenerateTrip,
            onDismiss: handleGeneratedTrip
        ) {
            GenerateTripBottomSheet(
                boardId: board.id,
                boardName: board.title,
                pins: pins,
                onGenerated: { trip in generatedTrip = trip }
            )
        }
        .sheet(isPresented: $isEditingBoard) {
            CreateBoardBottomSheet(editingBoard: board) { updated in
                // Update the row immediately (title/fallbacks read from `board`),
                // then re-fetch the detail so the derived `detail?.X ?? board.X`
                // props don't shadow the edit with stale values.
                board = updated
                Task { await refresh() }
            }
        }
        .fullScreenCover(
            item: $selectedPin,
            onDismiss: {
                // If the user tapped "Add to Trip", the detail cover was
                // dismissed to free the sheet slot — now present the trip picker.
                // Sequencing avoids stacking two system sheets (the detail is now
                // itself a native sheet inside LocationDetailView).
                if pendingPlanLocation != nil {
                    isAddingPinToTrip = true
                }
            }
        ) { pin in
            LocationDetailView(
                initialLocationName: pin.name,
                initialLocationAddress: pin.address ?? pin.notes ?? "",
                initialLatitude: pin.latitude ?? 0,
                initialLongitude: pin.longitude ?? 0,
                userLocation: nil,
                showsAddToPlan: true,
                addToPlanButtonTitle: String(localized: "Add to Trip"),
                onAddToPlan: { name, address, lat, lng in
                    pendingPlanLocation = PendingPlanLocation(
                        name: name,
                        address: address,
                        latitude: lat,
                        longitude: lng
                    )
                    // Dismiss the detail cover; its onDismiss presents the picker.
                    selectedPin = nil
                }
            )
        }
        .sheet(
            isPresented: $isAddingPinToTrip,
            onDismiss: {
                let outcome = addToTripOutcome
                pendingPlanLocation = nil
                addToTripOutcome = nil
                if case .failure(let message) = outcome {
                    addToTripErrorMessage = message
                }
            }
        ) {
            AddingPinToTripBottomSheet(
                trips: tripOptions,
                onSelectTrip: { option in
                    if let id = Int(option.id) {
                        attachPin(toTripId: id)
                    }
                }
            )
        }
        .alert(
            "Couldn't add to trip",
            isPresented: Binding(
                get: { addToTripErrorMessage != nil },
                set: { if !$0 { addToTripErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { addToTripErrorMessage = nil }
        } message: {
            Text(addToTripErrorMessage ?? "")
        }
        .task {
            await refresh()
        }
        .task {
            await tripService.listMyTrips()
        }
        .overlay {
            if isLoading && detail == nil {
                ProgressView()
            } else if let loadError, detail == nil {
                ContentUnavailableView {
                    Label(
                        "Couldn't load",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") {
                        Task { await refresh() }
                    }
                }
            }
        }
    }

    private var boardSummary: some View {
        BoardSummaryRow(
            board: board,
            coverImageUrl: coverImageUrl,
            descriptionText: descriptionText,
            locationLabel: locationLabel,
            variant: .detail
        )
    }

    private var generateTripLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
            Text("Generate me a trip")
                .font(.beVietnamPro(16, weight: .medium))
                .tracking(-0.32)
        }
        .foregroundStyle(Constants.White)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(
            Constants.BlueBase,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generate me a trip")
    }

    // Run once the generate sheet has fully dismissed: refresh the Trip tab list
    // and open the new trip on Your Plan.
    //
    // Navigation uses `.openTripDetail` (ProcessPinView's proven path) rather
    // than `.tripCreated`-with-tripId: the latter makes MainView hop
    // `.chat → .home → .trip`, and that extra tab transition double-fires
    // TripView's `onChange(…, initial: true)` push (the trip opened twice).
    // `.openTripDetail` switches straight to `.trip`, so it pushes exactly once.
    // We still post `.tripCreated` WITHOUT a tripId so MainView refreshes the
    // shared trip list while skipping its own (double-causing) navigation block.
    private func handleGeneratedTrip() {
        guard let trip = generatedTrip else { return }
        generatedTrip = nil
        DeepLinkRouter.shared.queuePlanRefresh(tripId: trip.id)
        NotificationCenter.default.post(name: .tripCreated, object: nil)
        NotificationCenter.default.post(
            name: .openTripDetail,
            object: nil,
            userInfo: ["tripId": trip.id]
        )
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await boardService.getBoard(boardId: board.id)
            loadError = nil
        } catch {
            print("BoardDetailView.refresh error: \(error)")
            loadError = "Couldn't load this board."
        }
    }

    private func performDelete() async {
        isDeletingBoard = true
        defer { isDeletingBoard = false }
        do {
            try await boardService.deleteBoard(boardId: board.id)
            dismiss()
        } catch {
            print("BoardDetailView.deleteBoard error: \(error)")
            deleteBoardErrorMessage = "Couldn't delete this board."
        }
    }

    private func deletePins(at offsets: IndexSet) {
        guard var currentPins = detail?.pins else { return }
        let toDelete = offsets.compactMap {
            currentPins.indices.contains($0) ? currentPins[$0] : nil
        }
        currentPins.remove(atOffsets: offsets)
        detail?.pins = currentPins
        Task {
            for pin in toDelete {
                do {
                    try await boardService.deletePin(
                        boardId: board.id,
                        pinId: pin.id
                    )
                } catch {
                    print("BoardDetailView.deletePin error: \(error)")
                    loadError = "Couldn't delete pin."
                    await refresh()
                    return
                }
            }
        }
    }

    private func attachPin(toTripId tripId: Int) {
        guard let location = pendingPlanLocation else { return }
        guard let userId = userProfileService.profile?.id else {
            addToTripOutcome = .failure("Sign in again before adding to a trip.")
            isAddingPinToTrip = false
            return
        }
        Task {
            let result = await tripDetailService.createPlanItem(
                tripId: tripId,
                title: location.name,
                planDate: nil,
                description: nil,
                location: location.address,
                latitude: location.latitude,
                longitude: location.longitude,
                address: location.address,
                startTime: "09:00",
                category: nil,
                userIds: [userId],
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: 1
            )
            switch result {
            case .success:
                NotificationCenter.default.post(
                    name: .marketplacePlanApplied,
                    object: tripId
                )
                // The notification above is lost when no TripDetailView is
                // mounted (user is on the Board tab). This one-shot survives
                // until the user opens the trip: TripDetailView.task consumes
                // it, jumps to Your Plan, and force-refreshes the plan items
                // (mirrors ProcessPinView's add-to-trip flow).
                DeepLinkRouter.shared.queuePlanRefresh(tripId: tripId)
                addToTripOutcome = .success
            case .failure:
                addToTripOutcome = .failure(
                    "Failed to add this place to the trip."
                )
            }
            isAddingPinToTrip = false
        }
    }
}

private struct BoardPinCountHeader: View {
    let pinCount: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(pinCount)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Constants.Neutral950)
                .lineSpacing(0)
                .shadow(color: Constants.Black.opacity(0.11), radius: 7.5)
                .contentTransition(.numericText(value: Double(pinCount)))
                .animation(.snappy(duration: 0.28), value: pinCount)
                .frame(maxWidth: .infinity)

            Text("Pins on this board")
                .font(.custom("Be Vietnam Pro", size: 20))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.8)
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

private struct PendingPlanLocation {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

private enum AddToTripOutcome {
    case success
    case failure(String)
}
