//
//  OngoingTripCache.swift
//  OnePlan
//
//  Disk cache of the ongoing trip's data so it can be read offline. An actor
//  that holds the canonical snapshot in memory and persists synchronously
//  inside the critical section — a disk read-modify-write across an `await`
//  would re-introduce the lost-update race the actor exists to prevent.
//
//  The persisted DTOs are generated (`Components.Schemas.*`) and have NO
//  serialization-stability guarantee across builds, so the cache is strictly
//  disposable: stamped with the app build version and discarded (file deleted)
//  on any decode failure or version mismatch, falling back to a network fetch.
//

import Foundation

/// One trip's cached slices. Fields are optional so each fetcher can persist
/// its slice independently without clobbering the others.
struct OngoingTripSnapshot: Codable, Sendable {
    var tripId: Int
    var schemaVersion: String
    var cachedAt: Double  // epoch seconds — strategy-independent, no Foundation.Date

    var summary: TripSummaryDto?
    var trip: TripDto?
    var budgets: [BudgetDto]?
    var expenses: [ExpenseSummaryDto]?
    var planItems: [PlanItemDto]?
    var breakdown: TripBreakdownDto?

    init(tripId: Int) {
        self.tripId = tripId
        self.schemaVersion = OngoingTripCache.currentSchemaVersion
        self.cachedAt = Date().timeIntervalSince1970
    }

    var cachedAtDate: Date { Date(timeIntervalSince1970: cachedAt) }
}

actor OngoingTripCache {
    static let shared = OngoingTripCache()

    /// App build number; any change discards every snapshot (regenerated DTOs
    /// may no longer decode against an older blob).
    static let currentSchemaVersion: String =
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"

    // Actor-isolated (not static) so the non-Sendable coders stay concurrency-safe.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var snapshots: [Int: OngoingTripSnapshot] = [:]
    private var hydrated = false

    private let directory: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("ongoing-trip-cache", isDirectory: true)
    }

    // MARK: - Public API (typed per-slice writers)

    func saveSummary(tripId: Int, _ summary: TripSummaryDto) {
        updateSlice(tripId: tripId) { $0.summary = summary }
    }

    func saveTripDetail(tripId: Int, trip: TripDto, budgets: [BudgetDto]) {
        updateSlice(tripId: tripId) {
            $0.trip = trip
            $0.budgets = budgets
        }
    }

    func saveExpenses(tripId: Int, _ expenses: [ExpenseSummaryDto]) {
        updateSlice(tripId: tripId) { $0.expenses = expenses }
    }

    func savePlanItems(tripId: Int, _ planItems: [PlanItemDto]) {
        updateSlice(tripId: tripId) { $0.planItems = planItems }
    }

    func saveBreakdown(tripId: Int, _ breakdown: TripBreakdownDto) {
        updateSlice(tripId: tripId) { $0.breakdown = breakdown }
    }

    /// Reads (and mutates) a trip's snapshot, then persists synchronously. The
    /// `mutate` closure runs entirely on the actor with no suspension, so there
    /// is no reentrancy window between concurrent slice writes.
    private func updateSlice(tripId: Int, _ mutate: (inout OngoingTripSnapshot) -> Void) {
        hydrateIfNeeded()
        var snapshot = snapshots[tripId] ?? OngoingTripSnapshot(tripId: tripId)
        mutate(&snapshot)
        snapshot.schemaVersion = Self.currentSchemaVersion
        snapshot.cachedAt = Date().timeIntervalSince1970
        snapshots[tripId] = snapshot
        persist(snapshot)
    }

    func load(tripId: Int) -> OngoingTripSnapshot? {
        hydrateIfNeeded()
        return snapshots[tripId]
    }

    /// All cached snapshots (used by the trip-list offline fallback). Callers
    /// prune to the authoritative ongoing set via `keepOnly(tripIds:)`.
    func loadAll() -> [OngoingTripSnapshot] {
        hydrateIfNeeded()
        return Array(snapshots.values)
    }

    /// Removes any cached trip not in `tripIds` (e.g. trips that ended or are no
    /// longer ONGOING per the authoritative `listMyTrips` status).
    func keepOnly(tripIds: Set<Int>) {
        hydrateIfNeeded()
        for id in snapshots.keys where !tripIds.contains(id) {
            remove(tripId: id)
        }
    }

    func clear(tripId: Int) {
        hydrateIfNeeded()
        remove(tripId: tripId)
    }

    /// Wipes the entire cache (logout / privacy).
    func clearAll() {
        snapshots.removeAll()
        try? FileManager.default.removeItem(at: directory)
        hydrated = true  // directory now absent; nothing more to hydrate
    }

    // MARK: - Disk

    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let snapshot = try decoder.decode(OngoingTripSnapshot.self, from: data)
                // Discard snapshots written by a different build — regenerated
                // DTOs may have drifted and a partial decode is worse than none.
                guard snapshot.schemaVersion == Self.currentSchemaVersion else {
                    try? fm.removeItem(at: file)
                    continue
                }
                snapshots[snapshot.tripId] = snapshot
            } catch {
                // Corrupt or schema-drifted blob: delete and cold-start.
                try? fm.removeItem(at: file)
            }
        }
    }

    private func persist(_ snapshot: OngoingTripSnapshot) {
        do {
            try ensureDirectory()
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL(tripId: snapshot.tripId),
                           options: [.atomic, .completeFileProtection])
        } catch {
            // Best-effort cache; a failed write just means a future cold-start.
        }
    }

    private func remove(tripId: Int) {
        snapshots[tripId] = nil
        try? FileManager.default.removeItem(at: fileURL(tripId: tripId))
    }

    private func fileURL(tripId: Int) -> URL {
        directory.appendingPathComponent("trip-\(tripId).json", isDirectory: false)
    }

    private func ensureDirectory() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path) else { return }
        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        // Exclude from iCloud/iTunes backup at the DIRECTORY level — atomic
        // writes rename a new inode over each file and would drop a per-file
        // resource value, but the directory's flag persists.
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}
