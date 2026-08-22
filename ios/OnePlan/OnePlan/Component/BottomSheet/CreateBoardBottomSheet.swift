//
//  CreateBoardBottomSheet.swift
//  OnePlan
//

import PhotosUI
import SwiftUI

struct CreateBoardBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    // When non-nil the sheet runs in edit mode: fields are pre-filled and Save
    // calls updateBoard instead of createBoard. Kept as a defaulted stored
    // property (no explicit init) so the memberwise initializer — and the
    // existing zero-arg call sites — keep working.
    var editingBoard: BoardSummaryDto? = nil
    var onSave: (BoardSummaryDto) -> Void = { _ in }

    @State private var boardName = ""
    @State private var descriptionText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedCity: CityDto?
    @State private var selectedState: StateDto?
    @State private var selectedCountry: CountryDto?
    @State private var showLocationPicker = false
    @State private var isGeneratingDesc = false
    @State private var isCreating = false
    @State private var saveError: String?
    @State private var boardService = BoardService.shared
    @State private var storageService = StorageUploadService()
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        boardName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEditing: Bool { editingBoard != nil }

    private var locationLabel: String? {
        guard let country = selectedCountry, let state = selectedState else { return nil }
        if let city = selectedCity {
            return "\(city.name), \(state.name), \(country.name)"
        }
        return "\(state.name), \(country.name)"
    }

    // In edit mode, fall back to the board's existing label until the user
    // re-picks a location (BoardSummaryDto carries only the label + IDs, not
    // the City/State/Country objects the picker would need to pre-select).
    private var displayLocationLabel: String? {
        locationLabel ?? editingBoard?.locationLabel
    }

    private var canGenerateAIDesc: Bool {
        !trimmedName.isEmpty && selectedCountry != nil && !isGeneratingDesc
    }

    // Location is required. The picker always returns a state + country
    // (city is optional), so a displayable label means a valid location has
    // been chosen (or, in edit mode, already exists on the board).
    private var hasLocation: Bool {
        displayLocationLabel != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? String(localized: "Edit Board") : String(localized: "Create new Board"))
                .font(.custom("Be Vietnam Pro", size: 20))
                .foregroundStyle(Constants.Neutral950)

            formContent
            if let saveError {
                Text(saveError)
                    .font(.custom("Be Vietnam Pro", size: 13))
                    .foregroundStyle(Constants.Warning500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            saveButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Neutral50)
        .onAppear(perform: prefillIfNeeded)
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showLocationPicker) {
            TripLocationPickerSheet(isPresented: $showLocationPicker) { city, state, country in
                selectedCity = city
                selectedState = state
                selectedCountry = country
            }
        }
    }

    private var formContent: some View {
        VStack(spacing: 12) {
            coverImagePicker

            VStack(spacing: 4) {
                CreateBoardInfoRow(
                    title: "Board name",
                    placeholder: "Enter name",
                    text: $boardName
                )
                .focused($isNameFocused)

                locationRow
                descriptionCard
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var coverImagePicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(
                        color: Color(red: 0.2, green: 0.36, blue: 1).opacity(0.2),
                        radius: 11.8, x: 0, y: 0
                    )
            } else if let coverImageUrl = editingBoard?.coverImageUrl,
                      !coverImageUrl.isEmpty {
                CachedRemoteImage(
                    url: URL(string: coverImageUrl),
                    targetSize: CGSize(width: 200, height: 240)
                ) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image("boardPlaceholder").resizable().scaledToFill()
                }
                .frame(width: 100, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(
                    color: Color(red: 0.2, green: 0.36, blue: 1).opacity(0.2),
                    radius: 11.8, x: 0, y: 0
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(Constants.BlueBase)
                }
                .frame(width: 100, height: 120)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .inset(by: 0.5)
                        .stroke(
                            .black.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
                .shadow(
                    color: Color(red: 0.2, green: 0.36, blue: 1).opacity(0.2),
                    radius: 11.8, x: 0, y: 0
                )
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
    }

    private var locationRow: some View {
        Button {
            isNameFocused = false
            showLocationPicker = true
        } label: {
            HStack(spacing: 12) {
                (Text("Location").foregroundColor(Constants.ContentM)
                    + Text(" *").foregroundColor(Constants.Warning500))
                    .font(.custom("Be Vietnam Pro", size: 15))
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(displayLocationLabel ?? "Choose")
                    .font(.beVietnamPro(16, weight: .light))
                    .foregroundStyle(
                        displayLocationLabel == nil ? Constants.ContentL : Constants.ContentB
                    )
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Description")
                    .font(.custom("Be Vietnam Pro", size: 15))
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)

                Spacer(minLength: 12)

                aiGenerateButton
            }

            TextField(
                "Tap “Made by AI” to generate, or write your own…",
                text: $descriptionText,
                axis: .vertical
            )
            .font(.custom("Be Vietnam Pro", size: 14))
            .foregroundStyle(Constants.ContentB)
            .lineLimit(3...6)
            .lineSpacing(1)
            .textInputAutocapitalization(.sentences)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var aiGenerateButton: some View {
        Button {
            generateDescription()
        } label: {
            HStack(spacing: 4) {
                if isGeneratingDesc {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image("processPinStars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                        .opacity(canGenerateAIDesc ? 1 : 0.4)
                }

                Text("Made by AI")
                    .font(.beVietnamPro(12, weight: .medium))
                    .foregroundStyle(
                        canGenerateAIDesc ? Constants.ContentM : Constants.ContentL
                    )
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Constants.Neutral100, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canGenerateAIDesc)
    }

    private var saveButton: some View {
        PrimaryButton(title: "\(saveButtonTitle)") {
            save()
        }
        .disabled(isCreating || trimmedName.isEmpty || !hasLocation)
    }

    private var saveButtonTitle: String {
        if isCreating { return String(localized: "Saving...") }
        return isEditing ? String(localized: "Save changes") : String(localized: "Save new Board")
    }

    private func prefillIfNeeded() {
        guard let editingBoard, boardName.isEmpty else { return }
        boardName = editingBoard.title
        descriptionText = editingBoard.description ?? ""
    }

    private func generateDescription() {
        guard canGenerateAIDesc, let country = selectedCountry else { return }
        let title = trimmedName
        isNameFocused = false
        Task {
            isGeneratingDesc = true
            defer { isGeneratingDesc = false }
            do {
                let result = try await boardService.generateDescription(
                    title: title,
                    countryName: country.name,
                    stateName: selectedState?.name,
                    cityName: selectedCity?.name
                )
                descriptionText = result
            } catch {
                print("CreateBoardBottomSheet.generateDescription error: \(error)")
                let place = locationLabel ?? title
                descriptionText =
                    String(localized: "A collection of pins from \(place). Save the spots you love and plan your next trip.", comment: "%@ = place name; AI description fallback")
            }
        }
    }

    private func save() {
        let title = trimmedName
        guard !title.isEmpty else { return }
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        saveError = nil
        if let editingBoard {
            Task { await update(editingBoard, title: title, desc: desc) }
        } else {
            Task { await create(title: title, desc: desc) }
        }
    }

    private func create(title: String, desc: String) async {
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await boardService.createBoard(
                title: title,
                description: desc.isEmpty ? nil : desc,
                coverImageUrl: nil,
                cityId: selectedCity.map { $0.id },
                stateId: selectedState.map { $0.id },
                countryId: selectedCountry.map { $0.id }
            )

            var finalBoard = created
            if let image = selectedImage {
                do {
                    let uploadResult = try await storageService.uploadImage(
                        image,
                        target: .board_hyphen_cover,
                        entityId: created.id
                    )
                    if let updated = boardService.updateLocalCoverImageUrl(
                        boardId: created.id,
                        coverImageUrl: uploadResult.url
                    ) {
                        finalBoard = updated
                    }
                } catch {
                    print("Board cover upload failed: \(error)")
                }
            }

            onSave(finalBoard)
            dismiss()
        } catch {
            print("CreateBoardBottomSheet.save error: \(error)")
            saveError = String(localized: "Failed to create board.")
        }
    }

    private func update(_ board: BoardSummaryDto, title: String, desc: String) async {
        isCreating = true
        defer { isCreating = false }

        // Only override the stored location when the user actually re-picked one;
        // otherwise keep the board's existing IDs (sending nil would clear them).
        let repicked = selectedCountry != nil
        let cityId = repicked ? selectedCity?.id : board.cityId
        let stateId = repicked ? selectedState?.id : board.stateId
        let countryId = repicked ? selectedCountry?.id : board.countryId

        do {
            var updated = try await boardService.updateBoard(
                boardId: board.id,
                title: title,
                description: desc.isEmpty ? nil : desc,
                cityId: cityId,
                stateId: stateId,
                countryId: countryId
            )

            // A newly chosen cover is persisted server-side by confirmUpload;
            // reflect it locally too.
            if let image = selectedImage {
                do {
                    let uploadResult = try await storageService.uploadImage(
                        image,
                        target: .board_hyphen_cover,
                        entityId: board.id
                    )
                    if let withCover = boardService.updateLocalCoverImageUrl(
                        boardId: board.id,
                        coverImageUrl: uploadResult.url
                    ) {
                        updated = withCover
                    }
                } catch {
                    print("Board cover upload failed: \(error)")
                }
            }

            onSave(updated)
            dismiss()
        } catch {
            print("CreateBoardBottomSheet.update error: \(error)")
            saveError = String(localized: "Failed to update board.")
        }
    }
}

private struct CreateBoardInfoRow: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.custom("Be Vietnam Pro", size: 15))
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 12)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundColor(Constants.ContentL)
            )
                .font(.beVietnamPro(16, weight: .light))
                .foregroundStyle(Constants.ContentB)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CreateBoardBottomSheet()
        }
}
