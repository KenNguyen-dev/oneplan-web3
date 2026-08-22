//
//  ProcessPinView.swift
//  OnePlan
//
//  Created by ken on 11/5/26.
//

import CoreLocation
import StoreKit
import SwiftUI

struct ProcessPinView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfileService.self) private var userProfileService
    @Environment(StoreManager.self) private var storeManager

    // Exactly one of these is set. sourceUrl drives a fresh extraction;
    // sessionId resumes an in-flight or terminal session (e.g. from a push
    // tap or BoardScanningCard).
    let sourceUrl: String?
    let sessionId: String?

    init(sourceUrl: String) {
        self.sourceUrl = sourceUrl
        self.sessionId = nil
    }

    init(sessionId: String) {
        self.sourceUrl = nil
        self.sessionId = sessionId
    }

    @State private var enableMainBorder: Bool = true
    @State private var showColors: Bool = true
    // visiblePins is presentation-only (staggered reveal of pins). The
    // source of truth lives on `sessionService.pins`; this array tracks
    // which pins have actually appeared on screen.
    @State private var visiblePins: [ExtractedPinDto] = []
    @State private var selectedPinIndexes: Set<Int> = []
    @State private var settledPinIndexes: Set<Int> = []
    @State private var scanningMessage = "Catching the spots..."
    // Local errors from "Add to Board / Trip" actions — distinct from the
    // service's extraction failureMessage so we don't conflate transport
    // errors with attach-flow errors.
    @State private var attachError: String?
    @State private var showsBackgroundProcessingBanner = true
    @State private var isAddingToBoard = false
    @State private var isAddingToTrip = false
    @State private var isCreatingBoard = false
    @State private var showQuotaSheet = false
    @State private var showBuyCredits = false
    @State private var isShowingSubscription = false
    @State private var boardService = BoardService.shared
    @State private var tripService = TripService()
    @State private var tripDetailService = TripDetailService()
    @State private var sessionService = PinExtractionSessionService.shared
    @State private var enrichmentService = PinEnrichmentService()
    @State private var enrichmentTasks: [Task<Void, Never>] = []
    // "New Trip" flow: pins are auto-saved to a fresh board, then handed to
    // GenerateTripBottomSheet (which requires persisted board pins).
    @State private var generateTripContext: GenerateTripContext?
    @State private var generatedTrip: TripDto?
    @State private var isPreparingGenerate = false

    private var identityKey: String { sessionId ?? sourceUrl ?? "" }

    // Extraction failures arrive as raw server/Gemini errors (e.g. a Vertex
    // 400 JSON blob). Never surface those to the user — show friendly copy.
    // Attach errors (Add to Board/Trip) are already user-friendly, so pass
    // them through verbatim.
    private var displayedFailure: String? {
        if sessionService.failureMessage != nil {
            return String(localized: "Couldn't analyze this post, please try again", comment: "Friendly fallback shown when pin extraction fails")
        }
        return attachError
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
        ScrollView {
            VStack(spacing: 15) {
                CustomBottomBar()
                    .borderBeam(
                        border: .white,
                        beam: showColors && !sessionService.streamFinished
                            ? [.green, .blue, .pink, .orange, .indigo] : [],
                        beamBlur: 15,
                        cornerRadius: 20,
                        isEnabled: enableMainBorder
                    )

                if let failure = displayedFailure {
                    failureCard(message: failure)
                }

                pinSections

                if !sessionService.streamFinished && sessionService.failureMessage == nil {
                    ProgressView()
                        .padding(.top, 12)
                }
            }
            .padding(15)
            .animation(revealAnimation, value: visiblePins.map(\.index))
            .animation(revealAnimation, value: settledPinIndexes)
            .animation(
                reduceMotion ? .default : .snappy(duration: 0.28),
                value: sessionService.streamFinished
            )
        }
        .scrollIndicators(.hidden)
        .background(Constants.Background)
        .task(id: identityKey) {
            await runExtraction()
        }
        .task(id: sessionService.streamFinished) {
            await rotateScanningMessages()
        }
        .task {
            await tripService.listMyTrips()
        }
        .onChange(of: sessionService.pins) { _, newValue in
            handleServicePinsUpdate(newValue)
        }
        .onDisappear {
            // Extraction continues server-side regardless. We only tear down
            // local presentation tasks here — the session service keeps the
            // SSE stream alive so a re-mount picks up where this left off.
            for task in enrichmentTasks { task.cancel() }
            enrichmentTasks.removeAll()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack {
                if !sessionService.streamFinished
                    && sessionService.failureMessage == nil
                    && showsBackgroundProcessingBanner {
                    runInBackgroundBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if sessionService.streamFinished && !visiblePins.isEmpty {
                    addToToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(
            reduceMotion ? .default : .snappy(duration: 0.28),
            value: sessionService.streamFinished
        )
        .animation(
            reduceMotion ? .default : .snappy(duration: 0.28),
            value: showsBackgroundProcessingBanner
        )
        .sheet(isPresented: $isAddingToBoard) {
            AddingPinToBoardBottomSheet(
                boards: boardService.boards.map { board in
                    AddingPinBoardOption(
                        id: String(board.id),
                        title: board.title,
                        description: board.description ?? "",
                        pinCount: board.pinCount,
                        location: board.locationLabel ?? "",
                        coverImageUrl: board.coverImageUrl
                    )
                },
                onSelectBoard: { option in
                    if let id = Int(option.id) {
                        attachPins(toBoardId: id)
                    }
                },
                onCreateBoard: {
                    isAddingToBoard = false
                    isCreatingBoard = true
                }
            )
        }
        .sheet(isPresented: $isCreatingBoard) {
            CreateBoardBottomSheet { created in
                attachPins(toBoardId: created.id)
            }
        }
        .modifier(
            CreditPaywallSheets(
                showQuotaSheet: $showQuotaSheet,
                showBuyCredits: $showBuyCredits,
                isShowingSubscription: $isShowingSubscription,
                sessionService: sessionService,
                storeManager: storeManager,
                onResolve: { dismiss() }
            )
        )
        .sheet(isPresented: $isAddingToTrip) {
            AddingPinToTripBottomSheet(
                trips: tripOptions,
                onSelectTrip: { option in
                    if let id = Int(option.id) {
                        attachPins(toTripId: id)
                    }
                },
                onNewTrip: { prepareGenerateTrip() }
            )
        }
        .modifier(
            GenerateTripSheet(
                context: $generateTripContext,
                onGenerated: { generatedTrip = $0 },
                onDismiss: { handleGeneratedTrip() }
            )
        )
    }

    // Pins grouped by the day the source video narrated ("Day 1"), days
    // ascending, arrival order preserved within a day. Pins with no day
    // mention collect in a trailing nil-keyed group. When NO pin has a day
    // (the common case for non-itinerary videos) this is a single nil group
    // and the list renders flat with no dividers.
    private var groupedVisiblePins: [(day: Int?, pins: [ExtractedPinDto])] {
        var pinsByDay: [Int?: [ExtractedPinDto]] = [:]
        for pin in visiblePins {
            pinsByDay[pin.dayNumber, default: []].append(pin)
        }
        let days = pinsByDay.keys.compactMap { $0 }.sorted()
        var groups: [(day: Int?, pins: [ExtractedPinDto])] =
            days.map { ($0, pinsByDay[$0] ?? []) }
        if let undated = pinsByDay[Int?.none] {
            groups.append((nil, undated))
        }
        return groups
    }

    private var pinSections: some View {
        let groups = groupedVisiblePins
        let showsDividers = groups.contains { $0.day != nil }
        // Position drives the unsettled stack visuals (scale/offset/zIndex);
        // number continuously across sections so the reveal stagger is
        // unchanged from the flat list.
        var position = 0
        var positionByPinIndex: [Int: Int] = [:]
        for group in groups {
            for pin in group.pins {
                positionByPinIndex[pin.index] = position
                position += 1
            }
        }

        return ForEach(groups, id: \.day) { group in
            if showsDividers {
                dayDivider(
                    group.day.map { String(localized: "Day \($0)") }
                        ?? String(localized: "More spots")
                )
                .transition(.opacity)
            }
            ForEach(group.pins, id: \.index) { pin in
                pinRow(pin, position: positionByPinIndex[pin.index] ?? 0)
            }
        }
    }

    private func pinRow(_ pin: ExtractedPinDto, position: Int) -> some View {
        Button {
            togglePinSelection(pin.index)
        } label: {
            BoardPinRow(
                pin: pin,
                position: position,
                isSettled: settledPinIndexes.contains(pin.index),
                isSelected: selectedPinIndexes.contains(pin.index),
                showsDay: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pin.name), pin")
        .accessibilityValue(
            selectedPinIndexes.contains(pin.index)
                ? "Selected"
                : "Not selected"
        )
        .transition(pinInsertionTransition)
        .zIndex(Double(visiblePins.count - position))
    }

    private func dayDivider(_ title: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Constants.BlueBase.opacity(0.18))
                .frame(height: 1)

            Text(title)
                .font(Font.beVietnamPro(13, weight: .medium))
                .tracking(-0.26)
                .foregroundStyle(Constants.Neutral600)
                .lineLimit(1)
                .fixedSize()

            Rectangle()
                .fill(Constants.BlueBase.opacity(0.18))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @MainActor
    private func runExtraction() async {
        // Cancel any in-flight enrichment tasks from a prior mount BEFORE
        // any await. We deliberately do NOT cancel the service stream —
        // it's owned across view mounts now.
        for task in enrichmentTasks { task.cancel() }
        enrichmentTasks.removeAll()
        visiblePins = []
        selectedPinIndexes = []
        settledPinIndexes = []
        scanningMessage = randomScanningMessage()
        showsBackgroundProcessingBanner = true
        await boardService.loadIfNeeded()

        if let sessionId {
            await sessionService.attach(sessionId: sessionId)
        } else if let sourceUrl {
            do {
                _ = try await sessionService.start(sourceUrl: sourceUrl)
            } catch let error as PinExtractionError
                where error.existingSessionId != nil
            {
                // User pasted URL B while URL A was running. Server tells
                // us A's id; attach to it instead of blocking the user.
                if let existing = error.existingSessionId {
                    await sessionService.attach(sessionId: existing)
                }
            } catch {
                // sessionService surfaces failure via its failureMessage
                // property; the body already reads from there.
                print("ProcessPinView.runExtraction error: \(error)")
            }
        }

        // Snapshot existing pins instantly on resume (no staggered reveal
        // for pins that were already extracted before this mount).
        let existing = sessionService.pins
        if !existing.isEmpty {
            visiblePins = existing
            selectedPinIndexes = Set(existing.map(\.index))
            settledPinIndexes = Set(existing.map(\.index))
            // Kick off enrichment for any that aren't verified yet.
            for pin in existing where !pin.isVerified {
                let pinIndex = pin.index
                let task = Task { @MainActor in
                    await enrichPin(index: pinIndex)
                }
                enrichmentTasks.append(task)
            }
        }
    }

    // Reacts to mutations on sessionService.pins driven by the SSE stream.
    // New arrivals get the staggered reveal animation; in-place updates
    // (e.g. enrichment writeback) are synced into visiblePins directly.
    @MainActor
    private func handleServicePinsUpdate(_ newPins: [ExtractedPinDto]) {
        for pin in newPins where !visiblePins.contains(where: { $0.index == pin.index }) {
            Task { @MainActor in await revealPin(pin) }
            let pinIndex = pin.index
            let task = Task { @MainActor in
                await enrichPin(index: pinIndex)
            }
            enrichmentTasks.append(task)
        }
        // Sync in-place mutations (enrichment results) onto visiblePins.
        for (i, vp) in visiblePins.enumerated() {
            if let updated = newPins.first(where: { $0.index == vp.index }),
               updated != vp {
                visiblePins[i] = updated
            }
        }
    }

    @MainActor
    private func revealPin(_ pin: ExtractedPinDto) async {
        guard !visiblePins.contains(where: { $0.index == pin.index }) else {
            return
        }

        if reduceMotion {
            visiblePins.append(pin)
            selectedPinIndexes.insert(pin.index)
            settledPinIndexes.insert(pin.index)
            return
        }

        withAnimation(revealAnimation) {
            visiblePins.append(pin)
            selectedPinIndexes.insert(pin.index)
        }

        try? await Task.sleep(for: .milliseconds(320))

        withAnimation(revealAnimation) {
            settledPinIndexes.insert(pin.index)
        }
    }

    @MainActor
    private func enrichPin(index: Int) async {
        guard let captured = sessionService.pins.first(where: { $0.index == index })
        else { return }
        // Already enriched (e.g. resumed from a re-mount that already ran
        // this for the same pin) — skip the network round-trip.
        if captured.isVerified { return }

        guard let result = await enrichmentService.enrich(
            name: captured.name,
            city: captured.city,
            country: captured.country
        ) else { return }
        guard !Task.isCancelled else { return }

        // Write through the service so a re-mount picks up enrichment too.
        // The onChange(of: sessionService.pins) handler syncs visiblePins.
        // A matched placemark can still format to an empty address (remote
        // POIs with no street/locality) — keep the model-emitted address
        // rather than overwriting it with "".
        let trimmedAddress = result.address
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmedAddress.isEmpty
            ? (captured.address ?? "")
            : trimmedAddress
        withAnimation(.easeInOut(duration: 0.25)) {
            sessionService.applyEnrichment(
                index: index,
                name: captured.name,
                address: address,
                latitude: result.coordinate.latitude,
                longitude: result.coordinate.longitude
            )
        }
    }

    private func attachPins(toTripId tripId: Int) {
        let payload = selectedPins
        guard !payload.isEmpty else { return }
        guard let userId = userProfileService.profile?.id else {
            attachError = "Sign in again before adding pins to a trip."
            return
        }
        Task {
            do {
                // Pins carry the day the source video narrated ("Day 1") when
                // available; group by it so plan items land on the right day.
                // The plan timeline only renders items with a startTime, so use
                // the video's time mention when parseable, else stagger 30
                // minutes apart from 09:00 within each day (clamped to 23:30).
                var offsetByDay: [Int: Int] = [:]
                for pin in payload {
                    let day = pin.dayNumber ?? 1
                    let offset = offsetByDay[day, default: 0]
                    offsetByDay[day] = offset + 1
                    let startTime: String
                    if let parsed = Self.parseTimeOfDay(pin.timeOfDayText) {
                        startTime = parsed
                    } else {
                        let totalMinutes = min(9 * 60 + offset * 30, 23 * 60 + 30)
                        startTime = String(
                            format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60
                        )
                    }
                    let result = await tripDetailService.createPlanItem(
                        tripId: tripId,
                        title: pin.name,
                        planDate: nil,
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
                        dayNumber: day
                    )
                    if case .failure(let error) = result {
                        throw error
                    }
                }
                AnalyticsClient.shared.track(
                    .PINS_SAVED,
                    properties: ["target": "trip", "pinCount": payload.count]
                )
                NotificationCenter.default.post(
                    name: .marketplacePlanApplied,
                    object: tripId
                )
                // Pins are now on the trip — the extraction session is
                // consumed, so clear it (same path as the card's Delete).
                await sessionService.dismiss()
                // One-shot intent the soon-to-mount TripDetailView consumes to
                // open on Your Plan + force-refresh (a NotificationCenter post
                // here is lost — TripDetailView mounts after the navigation).
                DeepLinkRouter.shared.queuePlanRefresh(tripId: tripId)
                // Ask MainView to switch to the Trip tab and push this trip's
                // detail (reuses the proven .tripCreated → deepLinkTripId path).
                NotificationCenter.default.post(
                    name: .openTripDetail,
                    object: nil,
                    userInfo: ["tripId": tripId]
                )
                isAddingToTrip = false
                // dismiss() pops ProcessPinView off MainView's stack while the
                // tab is still .chat; MainView then switches to .trip.
                dismiss()
            } catch {
                isAddingToTrip = false
                attachError = "Failed to add pins to trip."
            }
        }
    }

    // "New Trip" from the trip picker: GenerateTripBottomSheet only works on
    // persisted board pins, so create a board named after the video, save the
    // selected pins to it, then open the generator with the saved pins. The
    // board deliberately sticks around even if generation is cancelled.
    private func prepareGenerateTrip() {
        guard !isPreparingGenerate else { return }
        let inputs = selectedPinInputs(includeSchedule: true)
        guard !inputs.isEmpty else { return }
        isAddingToTrip = false
        isPreparingGenerate = true
        Task {
            defer { isPreparingGenerate = false }
            do {
                let rawTitle = (sessionService.videoDescription ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = rawTitle.isEmpty
                    ? String(localized: "Trip ideas")
                    : String(rawTitle.prefix(255))
                // Location is collected inside GenerateTripBottomSheet
                // (asksForLocation) and written onto this board before the
                // server generates — the trip's destination comes from it.
                let board = try await boardService.createBoard(title: title)
                let boardDto = try await boardService.addPins(
                    boardId: board.id,
                    pins: inputs
                )
                AnalyticsClient.shared.track(
                    .PINS_SAVED,
                    properties: ["target": "board", "pinCount": inputs.count]
                )
                generateTripContext = GenerateTripContext(
                    boardId: board.id,
                    boardName: board.title,
                    pins: boardDto.pins
                )
            } catch {
                print("ProcessPinView.prepareGenerateTrip error: \(error)")
                attachError = "Failed to prepare trip generation."
            }
        }
    }

    // onDismiss of the generate sheet. No generatedTrip means the user
    // cancelled — the auto-created board (with saved pins) remains, nothing
    // else to do.
    private func handleGeneratedTrip() {
        guard let trip = generatedTrip else { return }
        generatedTrip = nil
        Task { @MainActor in
            // Pins are consumed into a board + trip; clear the extraction
            // session (same path as the attachPins flows).
            await sessionService.dismiss()
            DeepLinkRouter.shared.queuePlanRefresh(tripId: trip.id)
            NotificationCenter.default.post(name: .tripCreated, object: nil)
            NotificationCenter.default.post(
                name: .openTripDetail,
                object: nil,
                userInfo: ["tripId": trip.id]
            )
            dismiss()
        }
    }

    // includeSchedule: the day/time narrated in the video only matters when
    // the pins are headed for a trip (the New Trip generate flow uses them as
    // arrangement hints). Plain "Add to Boards" saves without them.
    private func selectedPinInputs(includeSchedule: Bool) -> [PinInputDto] {
        let effectiveSourceUrl =
            sourceUrl ?? sessionService.activeSession?.sourceUrl ?? ""
        return selectedPins.map { pin in
            PinInputDto(
                name: pin.name,
                address: pin.address,
                latitude: pin.latitude,
                longitude: pin.longitude,
                notes: pin.notes,
                sourceUrl: effectiveSourceUrl,
                sourceTimestampSec: pin.sourceTimestampSec,
                category: pin.category,
                dayNumber: includeSchedule ? pin.dayNumber : nil,
                timeOfDayText: includeSchedule ? pin.timeOfDayText : nil
            )
        }
    }

    private func attachPins(toBoardId boardId: Int) {
        let payload = selectedPinInputs(includeSchedule: false)
        guard !payload.isEmpty else { return }
        Task {
            do {
                _ = try await boardService.addPins(
                    boardId: boardId,
                    pins: payload
                )
                AnalyticsClient.shared.track(
                    .PINS_SAVED,
                    properties: ["target": "board", "pinCount": payload.count]
                )
                // Pins are now on the board — the extraction session is
                // consumed, so clear it (same path as the card's Delete).
                await sessionService.dismiss()
                isAddingToBoard = false
                // BoardView is the SOLE owner of the board-path pop+push: it
                // sets pendingExtraction = nil (popping this view) then pushes
                // BoardDetailView. We deliberately do NOT call dismiss() here —
                // two independent owners of the same pop race with the push
                // (and the Create-Board sheet dismissing) on MainView's single
                // NavigationStack and SwiftUI can drop the push.
                NotificationCenter.default.post(
                    name: .openBoardDetail,
                    object: nil,
                    userInfo: ["boardId": boardId]
                )
            } catch {
                print("ProcessPinView.attachPins error: \(error)")
                isAddingToBoard = false
                attachError = "Failed to add pins to board."
            }
        }
    }

    // Normalizes a verbatim time mention from the video ("9am", "5:30 pm",
    // "morning") to the "HH:mm" startTime the plan timeline expects. Fuzzy
    // words map to representative times; anything unrecognized returns nil so
    // the caller falls back to the staggered default.
    static func parseTimeOfDay(_ text: String?) -> String? {
        guard let text = text?.lowercased() else { return nil }

        if let match = text.firstMatch(
            of: /(\d{1,2})(?::(\d{2}))?\s*(am|pm)/
        ) {
            var hour = Int(match.1) ?? 0
            let minute = match.2.flatMap { Int($0) } ?? 0
            guard (1...12).contains(hour), (0...59).contains(minute) else {
                return nil
            }
            if match.3 == "pm", hour != 12 { hour += 12 }
            if match.3 == "am", hour == 12 { hour = 0 }
            return String(format: "%02d:%02d", hour, minute)
        }

        let keywords: [(String, String)] = [
            ("sunrise", "06:00"),
            ("breakfast", "08:00"),
            ("morning", "09:00"),
            ("noon", "12:00"),
            ("lunch", "12:00"),
            ("afternoon", "14:00"),
            ("sunset", "17:30"),
            ("evening", "18:00"),
            ("dinner", "19:00"),
            ("night", "20:00")
        ]
        return keywords.first { text.contains($0.0) }?.1
    }

    private var selectedPins: [ExtractedPinDto] {
        sessionService.pins.filter { selectedPinIndexes.contains($0.index) }
    }

    private func togglePinSelection(_ index: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if selectedPinIndexes.contains(index) {
                selectedPinIndexes.remove(index)
            } else {
                selectedPinIndexes.insert(index)
            }
        }
    }

    private var addToToolbar: some View {
        HStack(spacing: 12) {
            SecondaryButton(title: "Add to Boards", variant: .dark) {
                triggerPrimaryHaptic()
                isAddingToBoard = true
            }
            .frame(maxWidth: .infinity)

            PrimaryButton(title: "Add to Trips") {
                isAddingToTrip = true
            }
            .frame(maxWidth: .infinity)
        }
        // Keep both button labels on a single line and shrink to fit — longer
        // localized titles (e.g. Vietnamese "Thêm vào chuyến đi") otherwise wrap
        // to two lines and leave the two buttons at mismatched heights.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .padding(.top, 14)
        //        .glassEffect(.regular.interactive())
        //        .padding(.bottom, 8)
        //        .background(.ultraThinMaterial)
        //        .background(Constants.Background.opacity(0.82))
    }

    private func triggerPrimaryHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private var runInBackgroundBanner: some View {
        HStack(spacing: 12) {
            Image("processPinBackgroundIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .background(Constants.White, in: .rect(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 15.642, y: 1.955)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Run in background")
                    .font(Font.custom("Be Vietnam Pro", size: 15))
                    .tracking(-0.3)

                Text("We’ll inform you when it’s done.")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
            }
            .foregroundStyle(Constants.White)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)

            Button {
                // Pop the view — extraction continues server-side and the
                // BoardScanningCard on BoardView takes over for progress.
                dismiss()
            } label: {
                Text("Close")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Constants.White, in: .capsule)
            }
            .buttonStyle(.plain)
            .layoutPriority(2)
            .accessibilityLabel("Run extraction in background")
        }
        .padding(12)
        .background(Constants.Black, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.09), radius: 8.95)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func CustomBottomBar() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            scanningHeader

            Rectangle()
                .fill(Constants.BlueBase.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 10) {
                Group {
                    if let url = sessionService.thumbnailURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .transition(.opacity)
                            case .empty, .failure:
                                Image("boardPlaceholder").resizable().scaledToFill()
                            @unknown default:
                                Image("boardPlaceholder").resizable().scaledToFill()
                            }
                        }
                        .id(url)
                    } else {
                        Image("boardPlaceholder").resizable().scaledToFill()
                    }
                }
                .frame(width: 57, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .background(Constants.Neutral100, in: .rect(cornerRadius: 12))
                .animation(.easeInOut(duration: 0.3), value: sessionService.thumbnailURL)

                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionService.videoDescription ?? "Getting clip information...")
                        .font(Font.custom("Be Vietnam Pro", size: 15))
                        .tracking(-0.75)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 3) {
                        Image("boardCompassIcon")
                            .resizable()
                            .frame(width: 14, height: 14)

                        Text(sourcePlatformLabel)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.Neutral600)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.white.opacity(0.5), in: .rect(cornerRadius: 20))
        .overlay {
            if sessionService.streamFinished {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Constants.BlueBase,
                        lineWidth: 2
                    )
            }
        }
        .shadow(color: .black.opacity(0.09), radius: 17.9)
        .accessibilityElement(children: .combine)
    }

    private var scanningHeader: some View {
        let finished = sessionService.streamFinished
        return HStack(spacing: finished ? 0 : 6) {
            if !finished {
                Image("processPinStars")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }

            Text(finished ? String(localized: "We found ") : scanningMessage)
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .foregroundStyle(Constants.ContentB)
                .id(finished ? "finished-title" : scanningMessage)
                .transition(scanningTextTransition)
            if finished {
                Text("\(sessionService.pins.count) pins in this post!")
                    .font(
                        Font.beVietnamPro(15, weight: .medium)
                    )
                    .foregroundStyle(Constants.BlueBase)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func rotateScanningMessages() async {
        guard !sessionService.streamFinished else { return }

        while !Task.isCancelled && !sessionService.streamFinished {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled && !sessionService.streamFinished else { return }

            let nextMessage = randomScanningMessage(excluding: scanningMessage)
            if reduceMotion {
                scanningMessage = nextMessage
            } else {
                withAnimation(.snappy(duration: 0.34, extraBounce: 0.04)) {
                    scanningMessage = nextMessage
                }
            }
        }
    }

    private func randomScanningMessage(excluding current: String? = nil)
        -> String
    {
        let candidates = Self.scanningMessages.filter { $0 != current }
        return (candidates.isEmpty ? Self.scanningMessages : candidates)
            .randomElement() ?? String(localized: "Catching the spots...")
    }

    private var scanningTextTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        )
    }

    private static let scanningMessages = [
        String(localized: "Catching the spots..."),
        String(localized: "Finding the good places..."),
        String(localized: "Pulling the pins..."),
        String(localized: "Spot hunting..."),
        String(localized: "Scanning the vibe..."),
        String(localized: "Finding the places worth saving..."),
        String(localized: "Turning the post into plans..."),
        String(localized: "Collecting the hot spots..."),
        String(localized: "Hunting down the recs..."),
        String(localized: "Saving the places from this post..."),
        String(localized: "Pulling the good stuff..."),
        String(localized: "Finding your next stop..."),
        String(localized: "Making this post plannable..."),
        String(localized: "Turning inspo into pins..."),
        String(localized: "From post to itinerary...")
    ]

    private var sourcePlatformLabel: String {
        let url = sourceUrl ?? sessionService.activeSession?.sourceUrl
        guard let url, let host = URL(string: url)?.host?.lowercased() else {
            return String(localized: "From video")
        }
        if host.contains("instagram") { return String(localized: "From Instagram") }
        if host.contains("tiktok") { return String(localized: "From TikTok") }
        return String(localized: "From video")
    }

    private var revealAnimation: Animation {
        reduceMotion ? .default : .snappy(duration: 0.46, extraBounce: 0.08)
    }

    private var pinInsertionTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }

    @ViewBuilder
    private func failureCard(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentB)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    @ViewBuilder
    func borderBeam(
        border: Color,
        hideFadeBorder: Bool = true,
        beam: [Color],
        beamBlur: CGFloat,
        cornerRadius: CGFloat,
        isEnabled: Bool = true
    ) -> some View {
        self
            .modifier(
                BorderBeamEffect(
                    border: border,
                    hideFadeBorder: hideFadeBorder,
                    beam: beam,
                    beamBlur: beamBlur,
                    cornerRadius: cornerRadius,
                    isEnabled: isEnabled
                )
            )
    }
}

struct BorderBeamEffect: ViewModifier {
    var border: Color
    var hideFadeBorder: Bool
    var beam: [Color]
    var beamBlur: CGFloat
    var cornerRadius: CGFloat
    var isEnabled: Bool
    func body(content: Content) -> some View {
        content
            .background {
                if isEnabled {
                    BorderBeamView()
                }
            }
    }

    @ViewBuilder
    private func BorderBeamView() -> some View {
        ZStack {
            if !hideFadeBorder {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(border.tertiary, lineWidth: 0.6)
            }

            KeyframeAnimator(initialValue: 0.0, repeating: true) { value in
                let rotation = value * 360

                let borderGradient = AngularGradient(
                    colors: [.clear, border, .clear],
                    center: .center,
                    startAngle: .degrees(140 + rotation),
                    endAngle: .degrees(270 + rotation)
                )

                let beamGradient = LinearGradient(
                    colors: beam,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(beamGradient)
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .blur(radius: beamBlur)
                                    .blendMode(.destinationOut)
                            }
                    }
                    .mask {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(borderGradient)
                            .blur(radius: beamBlur / 1.5)
                            .padding(-beamBlur * 2)
                    }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderGradient, lineWidth: 0.6)
            } keyframes: { _ in
                LinearKeyframe(1, duration: 2.5)
            }
        }
        .padding(0.5)
    }
}

#Preview {
    NavigationStack {
        ProcessPinView(sourceUrl: "https://www.instagram.com/reel/sample/")
    }
}

#Preview("Resume existing session") {
    NavigationStack {
        ProcessPinView(sessionId: "preview-session")
    }
}

// Everything GenerateTripBottomSheet needs, resolved once the pins are
// persisted. Item-driven so the sheet can't present with half-ready data.
struct GenerateTripContext: Identifiable {
    let boardId: Int
    let boardName: String
    let pins: [BoardPinDto]
    var id: Int { boardId }
}

// Kept out of ProcessPinView.body for the same reason as CreditPaywallSheets:
// the inline modifier chain exceeds the Swift type-checker's time budget.
private struct GenerateTripSheet: ViewModifier {
    @Binding var context: GenerateTripContext?
    let onGenerated: (TripDto) -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $context, onDismiss: onDismiss) { ctx in
                GenerateTripBottomSheet(
                    boardId: ctx.boardId,
                    boardName: ctx.boardName,
                    pins: ctx.pins,
                    asksForLocation: true,
                    onGenerated: onGenerated
                )
            }
    }
}

// Bundles the three scan-credit paywall sheets + the 402 trigger into one
// modifier. Keeping them out of ProcessPinView.body is required: inlined, the
// body's modifier chain exceeds the Swift type-checker's time budget.
// `onResolve` pops the host view (the extraction failed for lack of credits,
// so the user returns to Board) — preserving the pre-existing behavior.
private struct CreditPaywallSheets: ViewModifier {
    @Binding var showQuotaSheet: Bool
    @Binding var showBuyCredits: Bool
    @Binding var isShowingSubscription: Bool
    let sessionService: PinExtractionSessionService
    let storeManager: StoreManager
    let onResolve: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: $showQuotaSheet,
                onDismiss: {
                    // Swipe-to-dismiss path. The buttons clear lastCreditError
                    // BEFORE the sheet closes, so we only fall through here
                    // when the user dismissed without choosing — clean up so a
                    // repeat 402 with the same payload still re-presents.
                    if sessionService.lastCreditError != nil {
                        sessionService.clearCreditError()
                        onResolve()
                    }
                }
            ) {
                if let credits = sessionService.lastCreditError {
                    QuotaExceededSheet(
                        error: credits,
                        onBuyCredits: {
                            sessionService.clearCreditError()
                            showBuyCredits = true
                        },
                        onUpgrade: {
                            sessionService.clearCreditError()
                            isShowingSubscription = true
                        },
                        onDismiss: {
                            sessionService.clearCreditError()
                            onResolve()
                        }
                    )
                }
            }
            .sheet(isPresented: $showBuyCredits, onDismiss: onResolve) {
                BuyVideoExtractionQuotaBottomSheet(
                    packages: ScanCreditPackPresenter.packages(
                        from: storeManager.scanPackProducts
                    ),
                    onPurchase: { pkg in
                        // Sync callback; the sheet dismisses itself
                        // immediately. The purchase runs in the background and
                        // the badge refreshes via .scanCreditBalanceChanged.
                        Task {
                            if let product = storeManager.scanPackProducts
                                .first(where: { $0.id == pkg.id }) {
                                try? await storeManager
                                    .purchaseScanCredits(product)
                            }
                        }
                    }
                )
                .onAppear {
                    AnalyticsClient.shared.track(
                        .SCAN_CREDITS_PAYWALL_VIEWED,
                        properties: ["context": "extraction_402"]
                    )
                }
            }
            .sheet(isPresented: $isShowingSubscription, onDismiss: onResolve) {
                SubscriptionView()
            }
            .onChange(of: sessionService.lastCreditError) { _, newValue in
                showQuotaSheet = newValue != nil
            }
    }
}
