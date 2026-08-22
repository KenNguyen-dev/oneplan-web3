//
//  NoteService.swift
//  OnePlan
//
//  Trip-scoped notes/todos backed by the `trips/:tripId/notes` API. Owned by
//  TripDetailView (so it survives the tab-content `.id(selectedTab)` teardown)
//  and read by TripTodoSection. Mutations await the server and write the
//  returned row back in place — matching the rest of TripDetailService.
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias TripNoteDto = Components.Schemas.TripNoteDto

@MainActor
@Observable
final class NoteService {
    var notes: [TripNote] = []
    var isLoadingNotes = false
    var error: String?

    private var client: Client { APIClient.shared }

    /// Loads notes for the trip. Skips the network when already loaded unless
    /// `force` is set (mirrors the lazy-load gating used by sibling tabs).
    func fetchNotes(tripId: Int, force: Bool = false) async {
        if !force, !notes.isEmpty { return }
        isLoadingNotes = true
        defer { isLoadingNotes = false }
        do {
            let response = try await client.listTripNotes(.init(path: .init(tripId: tripId)))
            let dtos = try response.ok.body.json.data
            notes = dtos.map(TripNote.init(dto:))
        } catch {
            self.error = String(localized: "Failed to load notes")
        }
    }

    @discardableResult
    func createNote(
        tripId: Int,
        title: String,
        body: String,
        isDone: Bool
    ) async -> Bool {
        do {
            let response = try await client.createTripNote(.init(
                path: .init(tripId: tripId),
                body: .json(.init(title: title, body: body.isEmpty ? nil : body, isDone: isDone))
            ))
            let created = try response.created.body.json
            notes.insert(TripNote(dto: created), at: 0)
            return true
        } catch {
            self.error = String(localized: "Failed to create note")
            return false
        }
    }

    @discardableResult
    func setDone(tripId: Int, noteId: Int, isDone: Bool) async -> Bool {
        await update(tripId: tripId, noteId: noteId, body: .init(isDone: isDone))
    }

    @discardableResult
    func update(
        tripId: Int,
        noteId: Int,
        body: Components.Schemas.UpdateTripNoteDto
    ) async -> Bool {
        do {
            let response = try await client.updateTripNote(.init(
                path: .init(tripId: tripId, id: noteId),
                body: .json(body)
            ))
            let updated = try response.ok.body.json
            if let index = notes.firstIndex(where: { $0.id == noteId }) {
                notes[index] = TripNote(dto: updated)
            }
            return true
        } catch {
            self.error = String(localized: "Failed to update note")
            return false
        }
    }

    @discardableResult
    func deleteNote(tripId: Int, noteId: Int) async -> Bool {
        do {
            let response = try await client.deleteTripNote(.init(
                path: .init(tripId: tripId, id: noteId)
            ))
            _ = try response.noContent
            notes.removeAll { $0.id == noteId }
            return true
        } catch {
            self.error = String(localized: "Failed to delete note")
            return false
        }
    }
}
