//
//  AddNoteSheet.swift
//  OnePlan
//
//  Native bottom sheet for creating a new note/todo, matching the Figma design:
//  a centered title, a checkbox + title field, a multi-line note area, and a
//  prominent Save button.
//

import SwiftUI

struct AddNoteSheet: View {
    /// The note being edited, or `nil` when composing a new one.
    let note: TripNote?
    /// Called with the composed fields when the user taps Save. The server
    /// assigns the id, so the sheet hands back raw values rather than a `TripNote`.
    var onSave: (_ title: String, _ body: String, _ isDone: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var noteBody: String
    @State private var isDone: Bool
    @FocusState private var focusedField: Field?

    private enum Field { case title, body }

    init(
        note: TripNote? = nil,
        onSave: @escaping (_ title: String, _ body: String, _ isDone: Bool) -> Void
    ) {
        self.note = note
        self.onSave = onSave
        _title = State(initialValue: note?.title ?? "")
        _noteBody = State(initialValue: note?.body ?? "")
        _isDone = State(initialValue: note?.isDone ?? false)
    }

    private var isEditing: Bool { note != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 13) {
            Text(isEditing ? "Edit note" : "New note")
                .font(.beVietnamPro(20))
                .tracking(-0.8)
                .foregroundStyle(Constants.ContentB)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            VStack(spacing: 5) {
                titleField
                noteField
            }
            .frame(maxHeight: .infinity)

            PrimaryButton(title: "Save", action: save)
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .background(Constants.White)
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(44)
    }

    // MARK: - Title field (checkbox + single-line input)

    private var titleField: some View {
        HStack(spacing: 8) {
            Button {
                isDone.toggle()
            } label: {
                checkbox
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                if title.isEmpty {
                    Text("Title")
                        .font(.beVietnamPro(16, weight: .medium))
                        .tracking(-0.32)
                        .foregroundStyle(Constants.ContentL)
                }
                TextField("", text: $title)
                    .font(.beVietnamPro(16, weight: .medium))
                    .tracking(-0.32)
                    .foregroundStyle(Constants.ContentB)
                    .tint(Constants.BlueBase)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .body }
            }
        }
        .padding(20)
        .background(Constants.Neutral50)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isDone ? Constants.BlueBase : Constants.White)
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Constants.White)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Constants.Neutral200, lineWidth: 1)
                }
            }
            .frame(width: 20, height: 20)
    }

    // MARK: - Note field (multi-line text area)

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if noteBody.isEmpty {
                Text("Note")
                    .font(.beVietnamPro(15))
                    .tracking(-0.3)
                    .foregroundStyle(Constants.ContentL)
                    .padding(.top, 1)
            }
            TextEditor(text: $noteBody)
                .font(.beVietnamPro(15))
                .tracking(-0.3)
                .foregroundStyle(Constants.ContentB)
                .tint(Constants.BlueBase)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .body)
                // Counteract TextEditor's built-in text container insets so the
                // caret aligns with the placeholder.
                .padding(.leading, -5)
                .padding(.top, -8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(Constants.Neutral50)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        onSave(
            trimmedTitle,
            noteBody.trimmingCharacters(in: .whitespacesAndNewlines),
            isDone
        )
        dismiss()
    }
}

#Preview {
    Color(white: 0.85)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AddNoteSheet(onSave: { _, _, _ in })
        }
}
