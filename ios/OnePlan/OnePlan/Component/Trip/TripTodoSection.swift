//
//  TripTodoSection.swift
//  OnePlan
//
//  Todo tab content for the trip detail: a native List of note cards with
//  checkbox toggle + swipe-to-remove, plus a "New todo" button that presents
//  the AddNoteSheet. Notes are backed by the trips/:tripId/notes API via
//  NoteService, which is OWNED BY TripDetailView (not here) — the tab content
//  is recreated on every tab switch (`.id(selectedTab)`), so a service owned
//  here would re-fetch and flash empty each visit.
//

import SwiftUI

struct TripTodoSection: View {
    let service: NoteService
    let tripId: Int

    @State private var activeSheet: NoteSheet?
    @State private var contentHeight: CGFloat = 1

    /// Drives a single sheet for both composing a new note and editing one.
    private enum NoteSheet: Identifiable {
        case create
        case edit(TripNote)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let note): return "edit-\(note.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            notesContainer
            PrimaryButton(title: "New note") {
                activeSheet = .create
            }
        }
        // Claim the slack the trip detail's min-height scroll content provides
        // so the empty/loading container can fill the visible area.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                AddNoteSheet { title, body, isDone in
                    Task {
                        await service.createNote(
                            tripId: tripId,
                            title: title,
                            body: body,
                            isDone: isDone
                        )
                    }
                }
            case .edit(let note):
                AddNoteSheet(note: note) { title, body, isDone in
                    Task {
                        await service.update(
                            tripId: tripId,
                            noteId: note.id,
                            body: .init(title: title, body: body, isDone: isDone)
                        )
                    }
                }
            }
        }
    }

    // MARK: - White container (list / loading / empty)

    private var notesContainer: some View {
        Group {
            if service.isLoadingNotes && service.notes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.notes.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                notesList
            }
        }
        .padding(.vertical, 8)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("No notes yet")
                .font(.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentB)
            Text("Add your first note to get started")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Embedded note list

    // The trip detail hosts this inside an outer ScrollView, so the List is
    // scroll-disabled and sized to its content via a hidden measuring overlay —
    // the same pattern MemberList uses. Swipe actions still work in this mode.
    private var notesList: some View {
        List {
            ForEach(service.notes) { note in
                NoteCardRow(note: note, onTap: { activeSheet = .edit(note) }) {
                    Task {
                        await service.setDone(
                            tripId: tripId,
                            noteId: note.id,
                            isDone: !note.isDone
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await service.deleteNote(tripId: tripId, noteId: note.id)
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .tint(Constants.Secondary)
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            sizingContent
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TripTodoHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(TripTodoHeightPreferenceKey.self) { height in
            contentHeight = max(height, 1)
        }
        .frame(height: contentHeight)
    }

    /// Mirrors the visible rows (incl. their 4pt vertical + 8pt horizontal
    /// insets) so the List can be given an explicit height while scroll-disabled.
    private var sizingContent: some View {
        VStack(spacing: 8) {
            ForEach(service.notes) { note in
                NoteCardRow(note: note, onToggle: {})
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

private struct TripTodoHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    let service = NoteService()
    service.notes = TripNote.samples
    return ScrollView {
        TripTodoSection(service: service, tripId: 1)
            .padding(10)
    }
    .background(Constants.Background)
}
