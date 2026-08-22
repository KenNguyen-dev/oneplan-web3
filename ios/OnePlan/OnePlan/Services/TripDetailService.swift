//
//  TripDetailService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UIKit

typealias TripMemberDto = Components.Schemas.TripMemberDto
typealias BudgetDto = Components.Schemas.BudgetDto
typealias ExpenseSummaryDto = Components.Schemas.ExpenseSummaryDto
typealias PlanItemDto = Components.Schemas.PlanItemDto
typealias TripPhotoDto = Components.Schemas.TripPhotoDto
typealias TripPhotoListDto = Components.Schemas.TripPhotoListDto
typealias ExpenseDetailDto = Components.Schemas.ExpenseDto
typealias UpdateExpenseDto = Components.Schemas.UpdateExpenseDto
typealias TripBreakdownDto = Components.Schemas.TripBreakdownDto
typealias MemberBreakdownDto = Components.Schemas.MemberBreakdownDto
typealias BreakdownExpenseItemDto = Components.Schemas.BreakdownExpenseItemDto
typealias LeavePreviewDto = Components.Schemas.LeavePreviewDto
typealias LeavePreviewBudgetDto = Components.Schemas.LeavePreviewBudgetDto
typealias LeaveSettlementDto = Components.Schemas.LeaveSettlementDto
typealias LeaveSettlementExpenseDto = Components.Schemas.LeaveSettlementExpenseDto

enum ServiceError: LocalizedError {
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

@MainActor
@Observable
final class TripDetailService {
    enum StartTripResult {
        case success
        case blockedByMemberConflicts(memberNames: [String])
        case failure(message: String)
    }

    enum TripEndResult {
        case success
        case failure(message: String)
    }

    enum TripEndConsensusStartResult {
        case success(TripEndRequestDto)
        case failure(message: String)
    }

    // MARK: - State

    var trip: TripDto?
    var budgets: [BudgetDto] = []
    var expenses: [ExpenseSummaryDto] = []

    // MARK: - Computed (Currency)

    /// Group (home) currency of the trip. Nil until trip loads or if the
    /// server returned an unknown currency.
    var homeCurrency: Currency? {
        Currency(from: trip?.currency.value1)
    }

    /// Local currencies enabled for this trip (0 or 1 in v1; schema supports
    /// many for future multi-country trips).
    var localCurrencies: [Currency] {
        (trip?.localCurrencies ?? []).compactMap { apiCurrency in
            Currency(rawValue: apiCurrency.rawValue)
        }
    }

    /// Convenience: first local currency, if any.
    var primaryLocalCurrency: Currency? { localCurrencies.first }

    /// The set of currencies presented to the user in input dropdowns:
    /// home + locals, deduplicated, home first.
    var displayCurrencies: [Currency] {
        guard let home = homeCurrency else { return [] }
        var seen: Set<Currency> = [home]
        var result: [Currency] = [home]
        for cur in localCurrencies where !seen.contains(cur) {
            seen.insert(cur)
            result.append(cur)
        }
        return result
    }

    /// Home currency is immutable once budgets or expenses exist (server
    /// guards this too).
    var canEditHomeCurrency: Bool {
        budgets.isEmpty && expenses.isEmpty
    }

    // MARK: - State

    var allPlanItems: [PlanItemDto] = []
    var photos: [TripPhotoDto] = []

    /// Tracks the total number of planning days (may exceed max dayNumber in plan items).
    /// Used during PLANNING mode to allow adding empty days.
    var planningDayCount: Int = 1

    var isLoading = false
    var isLoadingExpenses = false
    var isLoadingPlanItems = false
    var isLoadingPhotos = false
    var isLoadingMorePhotos = false
    var isCreatingBudget = false
    var isUpdatingBudget = false
    var isDeletingBudget = false
    var isCreatingExpense = false
    var isCreatingPlanItem = false
    var isStartingTrip = false
    var isUpdatingSchedule = false
    var isEndingTrip = false
    var isDeletingTrip = false
    var isUploadingPhotos = false
    var uploadProgress: Double = 0
    var photosNextCursor: Int?
    var hasMorePhotos: Bool { photosNextCursor != nil }

    var expenseDetail: ExpenseDetailDto?
    var isLoadingExpenseDetail = false
    var isDeletingExpense = false
    var isUpdatingExpense = false
    var isDeletingPlanItem = false
    var isUpdatingPlanItem = false

    var breakdown: TripBreakdownDto?
    var isLoadingBreakdown = false
    var isSettlingAll = false

    var leavePreview: LeavePreviewDto?
    var isLoadingLeavePreview = false
    var isLeavingTrip = false

    var error: String?

    /// True when the currently-displayed data came from the offline cache
    /// rather than a live fetch. Drives the offline banner / read-only gating.
    var isServingCachedData = false
    /// When the cached data was last written (offline banner "updated …").
    var cachedAt: Date?

    private var client: Client { APIClient.shared }
    private let cache = OngoingTripCache.shared
    private let uploadService = StorageUploadService()

    // MARK: - Computed (Budget)

    var totalBudget: Double {
        budgets.reduce(0) { total, budget in
            total + budget.payments.filter(\.isPaid).reduce(0) { $0 + $1.amount }
        }
    }

    var totalSpent: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    var balance: Double { totalBudget - totalSpent }

    var usagePercent: Int {
        totalBudget > 0 ? max(Int(((totalBudget - totalSpent) / totalBudget) * 100), 0) : 0
    }

    var unsettledPaymentCount: Int {
        budgets.flatMap(\.payments).filter { !$0.isPaid }.count
    }

    // MARK: - Computed (History grouping)

    var groupedHistory: [(date: String, entries: [TripHistoryEntry])] {
        let expenseEntries = expenses.map { mapExpenseToEntry($0) }
        let budgetEntries = budgets.map { mapBudgetToEntry($0) }
        let allEntries = expenseEntries + budgetEntries

        let grouped = Dictionary(grouping: allEntries) { $0.dateKey }

        return grouped
            .map { (date: $0.key, entries: $0.value.sorted { $0.sortDate > $1.sortDate }) }
            .sorted { $0.date > $1.date }
    }

    var groupedBudgetHistory: [(date: String, entries: [TripHistoryEntry])] {
        groupedHistory.compactMap { group in
            let budgetEntries = group.entries.filter { $0.type == .budget }
            return budgetEntries.isEmpty ? nil : (date: group.date, entries: budgetEntries)
        }
    }

    // MARK: - Fetch methods

    func loadTripDetail(tripId: Int, force: Bool = false) async {
        // Return early if already loaded for this trip
        if !force, let trip = trip, trip.id == tripId {
            return
        }

        // Only set isLoading for initial load, not for force refresh (pull-to-refresh has its own indicator)
        if !force {
            isLoading = true
        }
        error = nil
        defer {
            if !force {
                isLoading = false
            }
        }

        do {
            // Fetch trip and budgets in PARALLEL to reduce cancellation window
            async let tripResp = client.getTrip(.init(path: .init(id: tripId)))
            async let budgetResp = client.listBudgets(.init(path: .init(tripId: tripId)))

            let (tripResult, budgetResult) = try await (tripResp, budgetResp)
            let loadedTrip = try tripResult.ok.body.json
            let loadedBudgets = try budgetResult.ok.body.json
            trip = loadedTrip
            budgets = loadedBudgets
            isServingCachedData = false
            await cache.saveTripDetail(tripId: tripId, trip: loadedTrip, budgets: loadedBudgets)
        } catch {
            if isOfflineError(error) {
                if let snapshot = await cache.load(tripId: tripId),
                   let cachedTrip = snapshot.trip {
                    trip = cachedTrip
                    budgets = snapshot.budgets ?? []
                    isServingCachedData = true
                    cachedAt = snapshot.cachedAtDate
                } else {
                    // Offline and this trip was never cached (e.g. a deep link to
                    // a non-ongoing trip).
                    self.error = String(localized: "You're offline. This trip isn't available offline.")
                }
            } else {
                self.error = String(localized: "Failed to load trip details")
            }
        }
    }

    func fetchExpenses(tripId: Int, force: Bool = false) async {
        // Skip the "already loading" guard for force refresh to avoid blocking
        if !force {
            guard !isLoadingExpenses else { return }
        }

        // Return early if already loaded (unless forced by a mutation refresh)
        if !force, !expenses.isEmpty {
            return
        }

        // Only set isLoadingExpenses for initial load, not for force refresh
        if !force {
            isLoadingExpenses = true
        }
        defer {
            if !force {
                isLoadingExpenses = false
            }
        }

        do {
            let response = try await client.listExpenses(.init(path: .init(tripId: tripId)))
            let loaded = try response.ok.body.json
            expenses = loaded
            isServingCachedData = false
            await cache.saveExpenses(tripId: tripId, loaded)
        } catch {
            if isOfflineError(error),
               let snapshot = await cache.load(tripId: tripId),
               let cached = snapshot.expenses {
                expenses = cached
                isServingCachedData = true
                cachedAt = snapshot.cachedAtDate
            } else {
                self.error = String(localized: "Failed to load expenses")
            }
        }
    }

    /// Fetches all plan items for a trip. Source of truth for both PLANNING and ONGOING modes.
    func fetchAllTripPlanItems(tripId: Int, force: Bool = false) async {
        if !force && !allPlanItems.isEmpty { return }
        // Only set isLoadingPlanItems for initial load, not for force refresh
        if !force {
            isLoadingPlanItems = true
        }
        defer {
            if !force {
                isLoadingPlanItems = false
            }
        }
        do {
            let response = try await client.listPlanItems(.init(
                path: .init(tripId: tripId),
                query: .init()
            ))
            allPlanItems = try response.ok.body.json
            // Initialize planningDayCount from max dayNumber in plan items
            let maxDay = allPlanItems.compactMap { $0.dayNumber }.map { Int($0) }.max() ?? 0
            planningDayCount = max(planningDayCount, maxDay, 1)
            // If trip is ONGOING, convert dayNumbers to planDates for display
            if trip?.status.value1 == .ONGOING {
                applyDayNumberToPlanDateConversion()
            }
            isServingCachedData = false
            // Persist AFTER conversion so cached plan items keep their planDates.
            await cache.savePlanItems(tripId: tripId, allPlanItems)
        } catch {
            if isOfflineError(error),
               let snapshot = await cache.load(tripId: tripId),
               let cached = snapshot.planItems {
                allPlanItems = cached
                let maxDay = cached.compactMap { $0.dayNumber }.map { Int($0) }.max() ?? 0
                planningDayCount = max(planningDayCount, maxDay, 1)
                // Safety net: fill any missing planDates from the cached trip's
                // startDate (no-op if already converted or trip not yet loaded).
                applyDayNumberToPlanDateConversion()
                isServingCachedData = true
                cachedAt = snapshot.cachedAtDate
            } else {
                self.error = String(localized: "Failed to load plan items")
            }
        }
    }

    /// Converts dayNumber to planDate locally for plans without planDate.
    /// Used when trip is ONGOING but plans were created during PLANNING.
    private func applyDayNumberToPlanDateConversion() {
        guard let startDateString = trip?.startDate else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Parse start date
        let startDate: Date?
        if let parsed = dateFormatter.date(from: startDateString) {
            startDate = parsed
        } else {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            startDate = isoFormatter.date(from: startDateString)
                ?? ISO8601DateFormatter().date(from: startDateString)
        }

        guard let tripStartDate = startDate else { return }

        for i in allPlanItems.indices {
            let plan = allPlanItems[i]
            if let dayNumber = plan.dayNumber,
               plan.planDate == nil || plan.planDate?.isEmpty == true {
                let daysToAdd = Int(dayNumber) - 1
                if let planDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: tripStartDate) {
                    allPlanItems[i].planDate = dateFormatter.string(from: planDate)
                }
            }
        }
    }

    func fetchPhotos(tripId: Int) async {
        guard !isLoadingPhotos else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        do {
            let response = try await client.listTripPhotos(.init(
                path: .init(tripId: tripId),
                query: .init(take: 20)
            ))
            let page = try response.ok.body.json
            photos = page.data
            photosNextCursor = page.nextCursor
        } catch {
            self.error = String(localized: "Failed to load photos")
        }
    }

    func fetchMorePhotos(tripId: Int) async {
        guard let cursor = photosNextCursor, !isLoadingMorePhotos else { return }
        isLoadingMorePhotos = true
        defer { isLoadingMorePhotos = false }

        do {
            let response = try await client.listTripPhotos(.init(
                path: .init(tripId: tripId),
                query: .init(cursor: cursor, take: 20)
            ))
            let page = try response.ok.body.json
            photos.append(contentsOf: page.data)
            photosNextCursor = page.nextCursor
        } catch {
            self.error = String(localized: "Failed to load more photos")
        }
    }

    func fetchAllPhotos(tripId: Int) async -> [TripPhotoDto] {
        var allPhotos = photos
        var cursor = photosNextCursor

        while let nextCursor = cursor {
            do {
                let response = try await client.listTripPhotos(.init(
                    path: .init(tripId: tripId),
                    query: .init(cursor: nextCursor, take: 50)
                ))
                let page = try response.ok.body.json
                allPhotos.append(contentsOf: page.data)
                cursor = page.nextCursor
            } catch {
                break
            }
        }
        return allPhotos
    }

    // MARK: - Update

    func updateTripName(tripId: Int, name: String) async {
        do {
            let response = try await client.updateTrip(.init(
                path: .init(id: tripId),
                body: .json(.init(name: name))
            ))
            trip = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to update trip name")
        }
    }

    /// Updates the trip's home (group) currency. Server rejects if budgets
    /// or expenses exist. Returns `true` on success; `false` on failure
    /// (sets `self.error`).
    func updateTripHomeCurrency(tripId: Int, currency: Currency) async -> Bool {
        guard let apiCurrency = currency.toAPICurrency else {
            self.error = String(localized: "Unsupported trip currency")
            return false
        }

        do {
            let response = try await client.updateTrip(.init(
                path: .init(id: tripId),
                body: .json(.init(
                    currency: .init(value1: apiCurrency)
                ))
            ))
            trip = try response.ok.body.json
            return true
        } catch {
            self.error = String(localized: "Failed to update trip currency")
            return false
        }
    }

    /// Updates the trip's local currencies list. Pass an empty array to
    /// clear. Returns `true` on success; `false` on failure (sets
    /// `self.error`).
    func updateTripLocalCurrencies(tripId: Int, currencies: [Currency]) async -> Bool {
        let apiCurrencies = currencies.compactMap(\.toAPICurrency)
        guard apiCurrencies.count == currencies.count else {
            self.error = String(localized: "Unsupported trip local currency")
            return false
        }

        do {
            let response = try await client.updateTrip(.init(
                path: .init(id: tripId),
                body: .json(.init(
                    localCurrencies: apiCurrencies
                ))
            ))
            trip = try response.ok.body.json
            return true
        } catch {
            self.error = String(localized: "Failed to update trip local currencies")
            return false
        }
    }

    func fetchLeavePreview(tripId: Int) async {
        guard !isLoadingLeavePreview else { return }
        isLoadingLeavePreview = true
        defer { isLoadingLeavePreview = false }

        do {
            let response = try await client.getLeavePreview(.init(
                path: .init(id: tripId)
            ))
            leavePreview = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to load leave preview")
        }
    }

    func leaveTrip(tripId: Int, userId: Int) async -> LeaveSettlementDto? {
        guard !isLeavingTrip else { return nil }
        isLeavingTrip = true
        defer { isLeavingTrip = false }

        do {
            let response = try await client.removeMember(.init(
                path: .init(id: tripId, userId: userId)
            ))
            return try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to leave trip")
            return nil
        }
    }

    /// Host marks a member's vault debt cleared so they may leave.
    func clearVaultLeave(tripId: Int, userId: Int) async -> Bool {
        do {
            let response = try await client.clearVaultLeave(
                .init(path: .init(id: tripId, userId: userId))
            )
            switch response {
            case .ok:
                return true
            case .undocumented(let code, _):
                return (200..<300).contains(code)
            default:
                // Legacy OpenAPI listed Nest's default POST 201 as `.created`.
                return true
            }
        } catch {
            self.error = String(localized: "Failed to mark member paid")
            return false
        }
    }

    /// Member announces vault leave (net must be >= 0). Host confirms next.
    func announceVaultLeave(tripId: Int) async -> Bool {
        do {
            let response = try await client.announceVaultLeave(
                .init(path: .init(id: tripId))
            )
            switch response {
            case .ok:
                break
            case .undocumented(let code, _):
                guard (200..<300).contains(code) else {
                    self.error = String(localized: "Failed to announce leave")
                    return false
                }
            default:
                break // legacy `.created`
            }
            await fetchLeavePreview(tripId: tripId)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func listVaultLeaveRequests(tripId: Int) async -> [Components.Schemas.VaultLeaveRequestDto] {
        do {
            return try await client.listVaultLeaveRequests(
                .init(path: .init(id: tripId))
            ).ok.body.json.items
        } catch {
            self.error = String(localized: "Failed to load leave requests")
            return []
        }
    }

    func confirmVaultLeave(tripId: Int, userId: Int) async -> Bool {
        do {
            let response = try await client.confirmVaultLeave(
                .init(path: .init(id: tripId, userId: userId))
            )
            // Nest POST defaulted to 201; reading only `.ok` (200) made a real
            // leave look like failure and showed "Could not confirm leave".
            switch response {
            case .ok:
                break
            case .undocumented(let code, _):
                guard (200..<300).contains(code) else {
                    self.error = String(localized: "Failed to confirm leave")
                    return false
                }
            default:
                break // legacy `.created`
            }
            removeMemberLocally(userId: userId)
            return true
        } catch {
            self.error = String(localized: "Failed to confirm leave")
            return false
        }
    }

    /// Optimistic members list update so the UI does not wait on reload.
    func removeMemberLocally(userId: Int) {
        guard var trip else { return }
        trip.members.removeAll { $0.userId == userId }
        self.trip = trip
    }

    /// Appoints or removes a co-host.
    ///
    /// Only the trip's creator may call this; the server enforces it, and the
    /// button is only shown to them.
    func setMemberRole(
        tripId: Int,
        userId: Int,
        role: Components.Schemas.TripMemberRole
    ) async -> Bool {
        do {
            _ = try await client.setMemberRole(.init(
                path: .init(id: tripId, userId: userId),
                body: .json(.init(role: .init(value1: role)))
            )).ok
            await loadTripDetail(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to change the member's role")
            return false
        }
    }

    func startTrip(
        tripId: Int,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> StartTripResult {
        guard !isStartingTrip else {
            return .failure(message: "Trip start is already in progress.")
        }

        isStartingTrip = true
        defer { isStartingTrip = false }

        do {
            let response = try await client.updateTrip(.init(
                path: .init(id: tripId),
                body: .json(.init(
                    startDate: startDate.map(Self.dateOnlyFormatter.string(from:)),
                    endDate: endDate.map(Self.dateOnlyFormatter.string(from:)),
                    status: .init(value1: .ONGOING)
                ))
            ))
            switch response {
            case .ok(let okResponse):
                trip = try okResponse.body.json
                // Server converts dayNumber→planDate during the ONGOING transition.
                // Refetch to pick up the server-populated planDates; fall back to
                // local conversion if the refetch fails for any reason.
                await fetchAllTripPlanItems(tripId: tripId, force: true)
                applyDayNumberToPlanDateConversion()
                return .success
            case .badRequest(let badRequest):
                let conflictError = try badRequest.body.json
                return .blockedByMemberConflicts(memberNames: conflictError.memberNames)
            case .forbidden:
                self.error = String(localized: "Failed to start trip")
                return .failure(message: "You don't have permission to start this trip.")
            case .undocumented(statusCode: let code, _):
                self.error = String(localized: "Failed to start trip")
                return .failure(message: "Failed to start trip (error \(code)).")
            }
        } catch {
            self.error = String(localized: "Failed to start trip")
            return .failure(message: "Failed to start trip. Please try again.")
        }
    }

    func endTrip(tripId: Int) async -> TripEndResult {
        guard !isEndingTrip else {
            return .failure(message: "Trip end is already in progress.")
        }
        isEndingTrip = true
        defer { isEndingTrip = false }

        do {
            let updateResp = try await client.updateTrip(.init(
                path: .init(id: tripId),
                body: .json(.init(status: .init(value1: .ENDED)))
            ))
            trip = try updateResp.ok.body.json
            return .success
        } catch {
            self.error = String(localized: "Failed to end trip")
            return .failure(message: "Failed to end trip. Please try again.")
        }
    }

    /// Vault trips only: start member consensus instead of setting ENDED.
    func requestVaultEndConsensus(tripId: Int) async -> TripEndConsensusStartResult {
        guard !isEndingTrip else {
            return .failure(message: "Trip end is already in progress.")
        }
        isEndingTrip = true
        defer { isEndingTrip = false }

        do {
            let request = try await TripEndConsensusService.shared.requestEnd(
                tripId: tripId
            )
            return .success(request)
        } catch TripEndConsensusService.ConsensusError.alreadyPending {
            do {
                if let existing = try await TripEndConsensusService.shared.getRequest(
                    tripId: tripId
                ) {
                    return .success(existing)
                }
            } catch {
                // fall through
            }
            return .failure(
                message: String(localized: "An end request is already waiting for approval.")
            )
        } catch {
            self.error = String(localized: "Failed to end trip")
            return .failure(
                message: error.localizedDescription
            )
        }
    }

    func fetchVaultEndRequest(tripId: Int) async -> TripEndRequestDto? {
        try? await TripEndConsensusService.shared.getRequest(tripId: tripId)
    }

    func deleteTrip(tripId: Int) async -> Bool {
        guard !isDeletingTrip else { return false }
        isDeletingTrip = true
        defer { isDeletingTrip = false }

        do {
            let response = try await client.deleteTrip(.init(
                path: .init(id: tripId)
            ))
            _ = try response.noContent
            return true
        } catch {
            self.error = String(localized: "Failed to delete trip")
            return false
        }
    }

    // MARK: - Breakdown

    func fetchBreakdown(tripId: Int, force: Bool = false) async {
        guard !isLoadingBreakdown else { return }
        if !force, breakdown != nil { return }
        isLoadingBreakdown = true
        defer { isLoadingBreakdown = false }

        do {
            let response = try await client.getTripBreakdown(
                .init(path: .init(tripId: tripId))
            )
            let loaded = try response.ok.body.json
            breakdown = loaded
            isServingCachedData = false
            await cache.saveBreakdown(tripId: tripId, loaded)
        } catch {
            if isOfflineError(error),
               let snapshot = await cache.load(tripId: tripId),
               let cached = snapshot.breakdown {
                breakdown = cached
                isServingCachedData = true
                cachedAt = snapshot.cachedAtDate
            } else {
                self.error = String(localized: "Failed to load breakdown")
            }
        }
    }

    func settleAllShares(tripId: Int) async -> Bool {
        guard !isSettlingAll else { return false }
        isSettlingAll = true
        defer { isSettlingAll = false }

        do {
            let response = try await client.settleAllShares(
                .init(path: .init(tripId: tripId))
            )
            breakdown = try response.ok.body.json
            return true
        } catch {
            self.error = String(localized: "Failed to settle shares")
            return false
        }
    }

    // MARK: - Create

    func createBudget(
        tripId: Int,
        name: String,
        amount: Double,
        originalAmount: Double? = nil,
        originalCurrency: Currency? = nil
    ) async -> Bool {
        isCreatingBudget = true
        defer { isCreatingBudget = false }
        let apiOriginalCurrency: Components.Schemas.Currency?
        if let originalCurrency {
            guard let converted = originalCurrency.toAPICurrency else {
                self.error = String(localized: "Unsupported original currency")
                return false
            }
            apiOriginalCurrency = converted
        } else {
            apiOriginalCurrency = nil
        }

        do {
            let response = try await client.createBudget(.init(
                path: .init(tripId: tripId),
                body: .json(.init(
                    name: name,
                    amount: amount,
                    originalAmount: originalAmount,
                    originalCurrency: apiOriginalCurrency.map { .init(value1: $0) }
                ))
            ))
            let newBudget = try response.created.body.json
            budgets.append(newBudget)
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to create budget")
            return false
        }
    }

    func updateBudget(
        tripId: Int,
        budgetId: Int,
        name: String?,
        amount: Double?,
        contributorUserIds: [Int]?,
        originalAmount: Double? = nil,
        originalCurrency: Currency? = nil
    ) async -> Bool {
        isUpdatingBudget = true
        defer { isUpdatingBudget = false }
        let apiOriginalCurrency: Components.Schemas.Currency?
        if let originalCurrency {
            guard let converted = originalCurrency.toAPICurrency else {
                self.error = String(localized: "Unsupported original currency")
                return false
            }
            apiOriginalCurrency = converted
        } else {
            apiOriginalCurrency = nil
        }

        do {
            let response = try await client.updateBudget(.init(
                path: .init(tripId: tripId, id: budgetId),
                body: .json(.init(
                    name: name,
                    amount: amount,
                    userIds: contributorUserIds?.map { Double($0) },
                    originalAmount: originalAmount,
                    originalCurrency: apiOriginalCurrency.map { .init(value1: $0) }
                ))
            ))
            let updatedBudget = try response.ok.body.json
            if let index = budgets.firstIndex(where: { Int($0.id) == budgetId }) {
                budgets[index] = updatedBudget
            } else {
                budgets.insert(updatedBudget, at: 0)
            }
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to update budget")
            return false
        }
    }

    func deleteBudget(tripId: Int, budgetId: Int) async -> Bool {
        isDeletingBudget = true
        defer { isDeletingBudget = false }

        do {
            let response = try await client.deleteBudget(.init(
                path: .init(tripId: tripId, id: budgetId)
            ))
            _ = try response.noContent
            budgets.removeAll { Int($0.id) == budgetId }
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to delete budget")
            return false
        }
    }

    func createExpense(
        tripId: Int, name: String, amount: Double,
        category: String, memberIds: [Int],
        originalAmount: Double? = nil,
        originalCurrency: Currency? = nil
    ) async -> Bool {
        isCreatingExpense = true
        defer { isCreatingExpense = false }
        let apiOriginalCurrency: Components.Schemas.Currency?
        if let originalCurrency {
            guard let converted = originalCurrency.toAPICurrency else {
                self.error = String(localized: "Unsupported original currency")
                return false
            }
            apiOriginalCurrency = converted
        } else {
            apiOriginalCurrency = nil
        }

        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let expenseDate = formatter.string(from: Date())

            let expenseCategory = Components.Schemas.ExpenseCategory(rawValue: category) ?? .OTHER

            let response = try await client.createExpense(.init(
                path: .init(tripId: tripId),
                body: .json(.init(
                    name: name,
                    amount: amount,
                    category: .init(value1: expenseCategory),
                    memberIds: memberIds,
                    expenseDate: expenseDate,
                    originalAmount: originalAmount,
                    originalCurrency: apiOriginalCurrency.map { .init(value1: $0) }
                ))
            ))
            let _ = try response.created.body.json
            // Refresh expenses list to get summary format
            await fetchExpenses(tripId: tripId, force: true)
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to create expense")
            return false
        }
    }

    func createExpenseFromReceipt(
        tripId: Int,
        restaurantName: String,
        items: [(name: String, amount: Double, userId: Int)],
        receiptNote: String,
        originalCurrency: Currency? = nil
    ) async -> Bool {
        isCreatingExpense = true
        defer { isCreatingExpense = false }

        // The receipt was scanned in `originalCurrency`; the server derives
        // the original total from the item-amount sum and converts to the
        // trip currency (same path as a manual expense via createExpense).
        let apiOriginalCurrency: Components.Schemas.Currency?
        if let originalCurrency {
            guard let converted = originalCurrency.toAPICurrency else {
                self.error = String(localized: "Unsupported original currency")
                return false
            }
            apiOriginalCurrency = converted
        } else {
            apiOriginalCurrency = nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expenseDate = formatter.string(from: Date())

        do {
            let receiptItems = items.map { item in
                Components.Schemas.ReceiptExpenseItemDto(
                    name: item.name,
                    amount: item.amount,
                    userId: item.userId
                )
            }

            print("[ReceiptExpense] Creating expense: name=\(restaurantName), items=\(items.count), tripId=\(tripId)")
            for (i, item) in items.enumerated() {
                print("[ReceiptExpense]   item[\(i)]: name=\(item.name), amount=\(item.amount), userId=\(item.userId)")
            }

            let response = try await client.createReceiptExpense(.init(
                path: .init(tripId: tripId),
                body: .json(.init(
                    name: restaurantName,
                    category: .init(value1: .FOOD),
                    note: receiptNote,
                    expenseDate: expenseDate,
                    items: receiptItems,
                    originalCurrency: apiOriginalCurrency.map { .init(value1: $0) }
                ))
            ))

            switch response {
            case .created(let created):
                let _ = try created.body.json
                print("[ReceiptExpense] Success: expense created")
            case .forbidden:
                print("[ReceiptExpense] Forbidden: not a trip member")
                self.error = String(localized: "You don't have access to this trip.")
                return false
            case .undocumented(statusCode: let code, _):
                print("[ReceiptExpense] Undocumented response (\(code))")
                self.error = String(localized: "Server error (\(code))")
                return false
            }
        } catch {
            print("[ReceiptExpense] Error: \(error)")
            self.error = String(localized: "Failed to create receipt expense: \(error.localizedDescription)")
            return false
        }

        await fetchExpenses(tripId: tripId, force: true)
        await fetchBreakdown(tripId: tripId, force: true)
        return true
    }

    func createPlanItem(
        tripId: Int,
        title: String,
        planDate: String? = nil,
        description: String?,
        location: String?,
        latitude: Double?,
        longitude: Double?,
        address: String?,
        startTime: String?,
        category: String?,
        userIds: [Int],
        voiceUrl: String?,
        voiceDuration: Int?,
        dayNumber: Int? = nil
    ) async -> Result<PlanItemDto, ServiceError> {
        isCreatingPlanItem = true
        defer { isCreatingPlanItem = false }
        do {
            let expenseCategory = category.flatMap {
                Components.Schemas.ExpenseCategory(rawValue: $0)
            }

            let response = try await client.createPlanItem(.init(
                path: .init(tripId: tripId),
                body: .json(.init(
                    title: title,
                    planDate: planDate,
                    dayNumber: dayNumber,
                    description: description,
                    location: location,
                    latitude: latitude,
                    longitude: longitude,
                    address: address,
                    startTime: startTime,
                    category: expenseCategory.map { .init(value1: $0) },
                    voiceUrl: voiceUrl,
                    voiceDuration: voiceDuration,
                    userIds: userIds.map { Double($0) }
                ))
            ))
            let newItem = try response.created.body.json
            allPlanItems.append(newItem)
            return .success(newItem)
        } catch {
            let message = String(localized: "Failed to create plan item")
            self.error = message
            return .failure(.failed(message: message))
        }
    }

    func updatePlanItem(
        tripId: Int,
        planItemId: Int,
        title: String?,
        planDate: String?,
        description: String?,
        location: String?,
        latitude: Double?,
        longitude: Double?,
        address: String?,
        startTime: String?,
        category: String?,
        userIds: [Int]?,
        voiceUrl: String?,
        voiceDuration: Int?,
        dayNumber: Int? = nil
    ) async -> Result<PlanItemDto, ServiceError> {
        isUpdatingPlanItem = true
        defer { isUpdatingPlanItem = false }

        do {
            let expenseCategory = category.flatMap {
                Components.Schemas.ExpenseCategory(rawValue: $0)
            }

            let response = try await client.updatePlanItem(.init(
                path: .init(tripId: tripId, id: planItemId),
                body: .json(.init(
                    title: title,
                    planDate: planDate,
                    description: description,
                    location: location,
                    latitude: latitude,
                    longitude: longitude,
                    address: address,
                    startTime: startTime,
                    category: expenseCategory.map { .init(value1: $0) },
                    voiceUrl: voiceUrl,
                    voiceDuration: voiceDuration,
                    dayNumber: dayNumber,
                    userIds: userIds?.map { Double($0) }
                ))
            ))
            let updatedItem = try response.ok.body.json

            if let allIndex = allPlanItems.firstIndex(where: { Int($0.id) == planItemId }) {
                allPlanItems[allIndex] = updatedItem
            }

            return .success(updatedItem)
        } catch {
            let message = String(localized: "Failed to update plan item")
            self.error = message
            return .failure(.failed(message: message))
        }
    }

    func uploadPhotos(tripId: Int, images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isUploadingPhotos = true
        uploadProgress = 0
        defer {
            isUploadingPhotos = false
            uploadProgress = 0
        }

        for (index, image) in images.enumerated() {
            do {
                _ = try await uploadService.uploadImage(
                    image,
                    target: .trip_hyphen_photo,
                    entityId: tripId
                )
                uploadProgress = Double(index + 1) / Double(images.count)
            } catch {
                self.error = String(localized: "Failed to upload photo \(index + 1)")
            }
        }

        await fetchPhotos(tripId: tripId)
    }

    func deletePhoto(tripId: Int, photoId: Int) async -> Bool {
        do {
            let response = try await client.deleteTripPhoto(.init(
                path: .init(tripId: tripId, id: photoId)
            ))
            _ = try response.noContent
            photos.removeAll { Int($0.id) == photoId }
            return true
        } catch {
            self.error = String(localized: "Failed to delete photo")
            return false
        }
    }

    // MARK: - Payment

    func markPayment(tripId: Int, budgetId: Int, paymentId: Int, isPaid: Bool) async -> Bool {
        do {
            let response = try await client.markBudgetPayment(.init(
                path: .init(tripId: tripId, id: budgetId, paymentId: paymentId),
                body: .json(.init(isPaid: isPaid))
            ))
            let updated = try response.ok.body.json
            if let bi = budgets.firstIndex(where: { $0.id == budgetId }),
               let pi = budgets[bi].payments.firstIndex(where: { $0.id == paymentId }) {
                budgets[bi].payments[pi] = updated
            }
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to update payment")
            return false
        }
    }

    // MARK: - Expense Detail

    var expenseIds: [Int] {
        expenses.map { Int($0.id) }
    }

    func fetchExpenseDetail(tripId: Int, expenseId: Int) async {
        guard !isLoadingExpenseDetail else { return }
        isLoadingExpenseDetail = true
        defer { isLoadingExpenseDetail = false }

        do {
            let response = try await client.getExpense(.init(
                path: .init(tripId: tripId, id: expenseId)
            ))
            expenseDetail = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to load expense details")
        }
    }

    func updateExpense(
        tripId: Int, expenseId: Int,
        name: String?,
        amount: Double?,
        category: String?,
        note: String?,
        expenseDate: String?,
        memberIds: [Int]?,
        originalAmount: Double? = nil,
        originalCurrency: Currency? = nil
    ) async -> Bool {
        isUpdatingExpense = true
        defer { isUpdatingExpense = false }
        let apiOriginalCurrency: Components.Schemas.Currency?
        if let originalCurrency {
            guard let converted = originalCurrency.toAPICurrency else {
                self.error = String(localized: "Unsupported original currency")
                return false
            }
            apiOriginalCurrency = converted
        } else {
            apiOriginalCurrency = nil
        }

        do {
            let expenseCategory = category.flatMap {
                Components.Schemas.ExpenseCategory(rawValue: $0)
            }

            let response = try await client.updateExpense(.init(
                path: .init(tripId: tripId, id: expenseId),
                body: .json(.init(
                    name: name,
                    amount: amount,
                    category: expenseCategory.map { .init(value1: $0) },
                    note: note,
                    expenseDate: expenseDate,
                    memberIds: memberIds,
                    originalAmount: originalAmount,
                    originalCurrency: apiOriginalCurrency.map { .init(value1: $0) }
                ))
            ))
            expenseDetail = try response.ok.body.json
            await fetchExpenses(tripId: tripId, force: true)
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to update expense")
            return false
        }
    }

    func deleteExpense(tripId: Int, expenseId: Int) async -> Bool {
        isDeletingExpense = true
        defer { isDeletingExpense = false }

        do {
            let response = try await client.deleteExpense(.init(
                path: .init(tripId: tripId, id: expenseId)
            ))
            _ = try response.noContent
            expenses.removeAll { Int($0.id) == expenseId }
            await fetchBreakdown(tripId: tripId, force: true)
            return true
        } catch {
            self.error = String(localized: "Failed to delete expense")
            return false
        }
    }

    func deletePlanItem(tripId: Int, planItemId: Int) async -> Result<Void, ServiceError> {
        isDeletingPlanItem = true
        defer { isDeletingPlanItem = false }

        do {
            let response = try await client.deletePlanItem(.init(
                path: .init(tripId: tripId, id: planItemId)
            ))
            _ = try response.noContent
            allPlanItems.removeAll { Int($0.id) == planItemId }
            return .success(())
        } catch {
            let message = String(localized: "Failed to delete plan")
            self.error = message
            return .failure(.failed(message: message))
        }
    }

    // MARK: - Mapping

    private func mapExpenseToEntry(_ expense: ExpenseSummaryDto) -> TripHistoryEntry {
        let category =
            CategoryChip.Category(apiValue: expense.category.value1.rawValue)
            ?? .other
        let categoryIcon = category.darkIconName
        let categorySystemIcon = category == .other ? "ellipsis" : nil

        let totalMemberCount = trip?.members.count ?? 0
        let isAll = expense.sharedMembers.count >= totalMemberCount && totalMemberCount > 0
        let scopeLabel = isAll ? "All" : ""
        let scopeMembers: [TripHistoryScopeMember] = isAll
            ? []
            : expense.sharedMembers.map {
                TripHistoryScopeMember(
                    id: Int($0.userId),
                    avatarUrl: $0.avatarUrl
                )
            }
        let participantLabel = ""
        let participantVariant: Chip.Variant = .neutral

        let currencySymbol = Currency(from: trip?.currency.value1)?.symbol ?? "đ"
        let formattedAmount = "-\(formatCurrency(expense.amount))\(currencySymbol)"

        // History cards should reflect the editable expense date/time, not creation time.
        let parsedDate = parseISO8601(expense.expenseDate)

        let timeString: String = {
            guard let date = parsedDate else { return "" }
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return timeFormatter.string(from: date)
        }()

        // NOTE: `ExpenseSummaryDto` does not currently carry
        // `originalAmount` / `originalCurrency`, so the list-row subtext is
        // not populated for expense rows today. When the summary DTO is
        // extended server-side, replace this with the same builder used in
        // `mapBudgetToEntry` below.
        let originalSubtext: String? = nil

        return TripHistoryEntry(
            title: expense.name,
            scopeLabel: scopeLabel,
            scopeMembers: scopeMembers,
            participantLabel: participantLabel,
            participantVariant: participantVariant,
            amount: formattedAmount,
            time: timeString,
            iconName: categoryIcon,
            systemIconName: categorySystemIcon,
            expenseId: Int(expense.id),
            dateKey: String(expense.expenseDate.prefix(10)),
            sortDate: parsedDate ?? .distantPast,
            originalSubtext: originalSubtext
        )
    }

    private func mapBudgetToEntry(_ budget: BudgetDto) -> TripHistoryEntry {
        let paidCount = budget.payments.filter { $0.isPaid }.count
        let totalCount = budget.payments.count
        let paidText = "\(paidCount)/\(totalCount) paid"
        let budgetTotal = budget.payments.reduce(0) { $0 + $1.amount }
        let currencySymbol = Currency(from: trip?.currency.value1)?.symbol ?? "đ"
        let formattedAmount = "+\(formatCurrency(budgetTotal))\(currencySymbol)"
        let parsedDate = parseISO8601(budget.createdAt)

        let homeCur = homeCurrency
        let origCur = budget.originalCurrency.flatMap { Currency(from: $0.value1) }
        let origAmt = budget.originalAmount
        let originalSubtext: String? = {
            guard let origCur, let origAmt, let homeCur, origCur != homeCur else {
                return nil
            }
            let whole = CurrencyFormatter.formatWhole(origAmt)
            let decimal = origCur.decimalPlaces > 0
                ? CurrencyFormatter.formatDecimal(origAmt)
                : ""
            return "~\(whole)\(decimal) \(origCur.rawValue)"
        }()

        return TripHistoryEntry(
            title: budget.name,
            scopeLabel: "",
            participantLabel: "Group",
            participantVariant: .green,
            amount: formattedAmount,
            time: paidText,
            iconName: "",
            systemIconName: "creditcard",
            type: .budget,
            budgetId: Int(budget.id),
            dateKey: String(budget.createdAt.prefix(10)),
            sortDate: parsedDate ?? .distantPast,
            originalSubtext: originalSubtext
        )
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Date helpers

    static func formatDateLabel(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"
        return displayFormatter.string(from: date)
    }

    /// Returns all day numbers from 1 to the maximum day found in plan items.
    /// Always includes at least Day 1.
    static func unlockedDayNumbers(from items: [PlanItemDto]) -> [Int] {
        let dayNumbers = items.compactMap { $0.dayNumber }.map { Int($0) }
        let maxDay = dayNumbers.max() ?? 1
        return Array(1...maxDay)
    }

    /// Returns all day numbers from 1 to the effective day count.
    /// When the trip has both `startDate` and `endDate` set, the count is
    /// derived from the date range. Otherwise it falls back to the manual
    /// `planningDayCount`.
    func availablePlanningDays() -> [Int] {
        if let count = scheduledDayCount() {
            return Array(1...max(count, 1))
        }
        return Array(1...max(planningDayCount, 1))
    }

    /// Number of calendar days in `[startDate, endDate]` inclusive, or `nil`
    /// when either bound is missing or invalid.
    func scheduledDayCount() -> Int? {
        guard
            let start = parsedTripDate(trip?.startDate),
            let end = parsedTripDate(trip?.endDate)
        else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard
            let days = calendar.dateComponents([.day], from: startDay, to: endDay).day,
            days >= 0
        else { return nil }
        return days + 1
    }

    /// Date corresponding to a 1-based day number, given the trip's
    /// `startDate`. Returns `nil` if `startDate` is unset.
    func planDate(forDay day: Int) -> Date? {
        guard
            day >= 1,
            let start = parsedTripDate(trip?.startDate)
        else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: day - 1, to: calendar.startOfDay(for: start))
    }

    /// `yyyy-MM-dd` string for the date corresponding to a 1-based day number.
    func planDateString(forDay day: Int) -> String? {
        planDate(forDay: day).map(Self.dateOnlyFormatter.string(from:))
    }

    /// Adds a day to the planning surface. When dates are set, extends
    /// `endDate` by one day. Otherwise increments the manual counter (max 14).
    func addPlanningDay() {
        if let start = parsedTripDate(trip?.startDate),
           let currentEnd = parsedTripDate(trip?.endDate),
           let tripId = trip?.id
        {
            let calendar = Calendar.current
            guard let newEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: currentEnd)
            ) else { return }
            // Optimistic local update so availablePlanningDays() reflects the
            // new range immediately; the server PATCH catches up below.
            trip?.endDate = Self.dateOnlyFormatter.string(from: newEnd)
            Task { _ = await self.updateTripSchedule(
                tripId: Int(tripId),
                startDate: start,
                endDate: newEnd
            ) }
            return
        }
        guard planningDayCount < 14 else { return }
        planningDayCount += 1
    }

    /// Deletes a day and shifts all subsequent plans down by one day number.
    /// Syncs changes to server. Also decrements planningDayCount and shrinks
    /// `endDate` by one day when the trip has both dates set.
    func deletePlanningDay(_ day: Int) {
        let currentCount = availablePlanningDays().count
        guard currentCount > 1, day >= 1, day <= currentCount else { return }
        guard let tripId = trip?.id else { return }

        // Find plans to delete and plans to shift
        let plansToDelete = allPlanItems.filter { item in
            guard let dayNumber = item.dayNumber else { return false }
            return Int(dayNumber) == day
        }
        let plansToShift = allPlanItems.filter { item in
            guard let dayNumber = item.dayNumber else { return false }
            return Int(dayNumber) > day
        }

        // Update local state immediately for responsiveness
        allPlanItems.removeAll { item in
            guard let dayNumber = item.dayNumber else { return false }
            return Int(dayNumber) == day
        }
        for i in allPlanItems.indices {
            if let currentDay = allPlanItems[i].dayNumber {
                let dayInt = Int(currentDay)
                if dayInt > day {
                    allPlanItems[i].dayNumber = dayInt - 1
                }
            }
        }
        // When both dates are set, optimistically shrink endDate locally so the
        // chip count tracks the calendar window; PATCH catches up below.
        var shrinkSchedule: (start: Date, end: Date)?
        if let start = parsedTripDate(trip?.startDate),
           let currentEnd = parsedTripDate(trip?.endDate)
        {
            let calendar = Calendar.current
            if let newEnd = calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.startOfDay(for: currentEnd)
            ), newEnd >= calendar.startOfDay(for: start) {
                trip?.endDate = Self.dateOnlyFormatter.string(from: newEnd)
                shrinkSchedule = (start, newEnd)
            }
        } else {
            planningDayCount = max(planningDayCount - 1, 1)
        }

        // Sync to server in background
        Task {
            // Delete plans on the deleted day
            for plan in plansToDelete {
                _ = try? await client.deletePlanItem(.init(
                    path: .init(tripId: Int(tripId), id: Int(plan.id))
                ))
            }

            // Update dayNumber for shifted plans
            for plan in plansToShift {
                guard let oldDayNumber = plan.dayNumber else { continue }
                let newDayNumber = Int(oldDayNumber) - 1
                _ = try? await client.updatePlanItem(.init(
                    path: .init(tripId: Int(tripId), id: Int(plan.id)),
                    body: .json(.init(dayNumber: newDayNumber))
                ))
            }

            if let shrink = shrinkSchedule {
                _ = await self.updateTripSchedule(
                    tripId: Int(tripId),
                    startDate: shrink.start,
                    endDate: shrink.end
                )
            }
        }
    }

    /// PATCHes the trip's `startDate`/`endDate` and truncates trailing
    /// items beyond the new range. Coalesces concurrent calls via
    /// `isUpdatingSchedule`; the latest in-flight wins.
    @discardableResult
    func updateTripSchedule(
        tripId: Int,
        startDate: Date?,
        endDate: Date?
    ) async -> Bool {
        guard !isUpdatingSchedule else { return false }
        isUpdatingSchedule = true
        defer { isUpdatingSchedule = false }

        let formatter = Self.dateOnlyFormatter
        do {
            let response = try await client.updateTrip(.init(
                path: .init(id: tripId),
                body: .json(.init(
                    startDate: startDate.map(formatter.string(from:)),
                    endDate: endDate.map(formatter.string(from:))
                ))
            ))
            trip = try response.ok.body.json
            truncatePlanItemsBeyondScheduledRange()
            // The server shifts item planDates whenever startDate changes on a
            // trip that already had a startDate. Refetch trip + plan items in
            // parallel so the chip strip and timeline reflect the new window
            // without requiring a manual pull-to-refresh.
            async let tripRefresh: () = loadTripDetail(tripId: tripId, force: true)
            async let itemsRefresh: () = fetchAllTripPlanItems(tripId: tripId, force: true)
            _ = await (tripRefresh, itemsRefresh)
            NotificationCenter.default.post(
                name: .tripScheduleUpdated,
                object: nil,
                userInfo: ["tripId": tripId]
            )
            return true
        } catch {
            self.error = String(localized: "Failed to update trip dates")
            return false
        }
    }

    /// Deletes plan items whose `dayNumber` exceeds the current scheduled
    /// day count. No-op if the trip has no scheduled range.
    private func truncatePlanItemsBeyondScheduledRange() {
        guard
            let count = scheduledDayCount(),
            let tripId = trip?.id
        else { return }
        let plansToDelete = allPlanItems.filter { item in
            guard let day = item.dayNumber else { return false }
            return Int(day) > count
        }
        guard !plansToDelete.isEmpty else { return }
        allPlanItems.removeAll { item in
            guard let day = item.dayNumber else { return false }
            return Int(day) > count
        }
        Task {
            for plan in plansToDelete {
                _ = try? await client.deletePlanItem(.init(
                    path: .init(tripId: Int(tripId), id: Int(plan.id))
                ))
            }
        }
    }

    /// Number of plan items on day numbers strictly greater than `count`.
    /// Used to drive the destructive-confirm alert when shrinking the range.
    func planItemCount(beyondDay count: Int) -> Int {
        allPlanItems.filter { item in
            guard let day = item.dayNumber else { return false }
            return Int(day) > count
        }.count
    }

    var tripStartDate: Date? { parsedTripDate(trip?.startDate) }
    var tripEndDate: Date? { parsedTripDate(trip?.endDate) }

    /// Parses a server date string (`yyyy-MM-dd` or ISO 8601) into a `Date`.
    private func parsedTripDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = Self.dateOnlyFormatter.date(from: value) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let isoNoFractional = ISO8601DateFormatter()
        isoNoFractional.formatOptions = [.withInternetDateTime]
        return isoNoFractional.date(from: value)
    }

    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    func rearrangePlanningDays(_ orderedDays: [Int]) {
        guard let tripId = trip?.id else { return }
        guard orderedDays.count == planningDayCount else { return }

        let dayMapping = Dictionary(
            uniqueKeysWithValues: orderedDays.enumerated().map { index, sourceDay in
                (sourceDay, index + 1)
            }
        )

        let changedPlans = allPlanItems.compactMap { item -> (id: Int, newDayNumber: Int)? in
            guard let currentDayNumber = item.dayNumber else { return nil }
            let currentDay = Int(currentDayNumber)
            guard let newDay = dayMapping[currentDay], newDay != currentDay else { return nil }
            return (Int(item.id), newDay)
        }

        guard !changedPlans.isEmpty else { return }

        for index in allPlanItems.indices {
            guard let currentDayNumber = allPlanItems[index].dayNumber else { continue }
            let currentDay = Int(currentDayNumber)
            if let newDay = dayMapping[currentDay] {
                allPlanItems[index].dayNumber = newDay
            }
        }

        Task {
            for plan in changedPlans {
                _ = try? await client.updatePlanItem(.init(
                    path: .init(tripId: Int(tripId), id: plan.id),
                    body: .json(.init(dayNumber: plan.newDayNumber))
                ))
            }
        }
    }

    func rearrangePlanDates(
        orderedDateValues: [String],
        slotDateValues: [String]
    ) {
        guard let tripId = trip?.id else { return }
        guard orderedDateValues.count == slotDateValues.count else { return }

        let dateMapping = Dictionary(
            uniqueKeysWithValues: zip(orderedDateValues, slotDateValues).map { sourceDate, targetDate in
                (sourceDate, targetDate)
            }
        )

        let changedPlans = allPlanItems.compactMap { item -> (id: Int, newPlanDate: String)? in
            guard let currentDate = item.planDate,
                  let newDate = dateMapping[currentDate],
                  newDate != currentDate else { return nil }
            return (Int(item.id), newDate)
        }

        guard !changedPlans.isEmpty else { return }

        for index in allPlanItems.indices {
            guard let currentDate = allPlanItems[index].planDate else { continue }
            if let newDate = dateMapping[currentDate] {
                allPlanItems[index].planDate = newDate
            }
        }

        Task {
            for plan in changedPlans {
                _ = try? await client.updatePlanItem(.init(
                    path: .init(tripId: Int(tripId), id: plan.id),
                    body: .json(.init(planDate: plan.newPlanDate))
                ))
            }
        }
    }

    func deletePlanItems(onDate dateValue: String, tripId: Int) {
        guard availablePlanningDays().count > 1 else { return }
        guard let deletedDate = parsedTripDate(dateValue),
              let start = parsedTripDate(trip?.startDate),
              let currentEnd = parsedTripDate(trip?.endDate)
        else { return }

        let calendar = Calendar.current
        let deletedDay = calendar.startOfDay(for: deletedDate)
        guard deletedDay >= calendar.startOfDay(for: start),
              deletedDay <= calendar.startOfDay(for: currentEnd)
        else { return }

        let plansToDelete = allPlanItems.filter { $0.planDate == dateValue }
        let plansToShift = allPlanItems.filter { item in
            guard let planDate = item.planDate,
                  let date = parsedTripDate(planDate)
            else { return false }
            return calendar.startOfDay(for: date) > deletedDay
        }

        // Optimistic local update: remove items on the deleted date, shift later
        // items back by one day, and shrink the trip's endDate.
        allPlanItems.removeAll { $0.planDate == dateValue }
        for i in allPlanItems.indices {
            guard let planDate = allPlanItems[i].planDate,
                  let date = parsedTripDate(planDate)
            else { continue }
            if calendar.startOfDay(for: date) > deletedDay,
               let newDate = calendar.date(byAdding: .day, value: -1, to: date)
            {
                allPlanItems[i].planDate = Self.dateOnlyFormatter.string(from: newDate)
            }
        }

        var shrinkSchedule: (start: Date, end: Date)?
        if let newEnd = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: currentEnd)
        ), newEnd >= calendar.startOfDay(for: start) {
            trip?.endDate = Self.dateOnlyFormatter.string(from: newEnd)
            shrinkSchedule = (start, newEnd)
        }

        Task {
            for plan in plansToDelete {
                _ = try? await client.deletePlanItem(.init(
                    path: .init(tripId: tripId, id: Int(plan.id))
                ))
            }

            for plan in plansToShift {
                guard let planDate = plan.planDate,
                      let date = parsedTripDate(planDate),
                      let newDate = calendar.date(byAdding: .day, value: -1, to: date)
                else { continue }
                let newPlanDate = Self.dateOnlyFormatter.string(from: newDate)
                _ = try? await client.updatePlanItem(.init(
                    path: .init(tripId: tripId, id: Int(plan.id)),
                    body: .json(.init(planDate: newPlanDate))
                ))
            }

            if let shrink = shrinkSchedule {
                _ = await self.updateTripSchedule(
                    tripId: tripId,
                    startDate: shrink.start,
                    endDate: shrink.end
                )
            }
        }
    }

}
