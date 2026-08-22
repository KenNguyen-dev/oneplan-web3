//
//  TripLocationPickerSheet.swift
//  OnePlan
//

import SwiftUI

struct TripLocationPickerSheet: View {
    @Binding var isPresented: Bool
    var onLocationSelected: (CityDto?, StateDto, CountryDto) -> Void

    @State private var service = LocationPickerService()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(
                    text: $searchText,
                    placeholder: "Search cities",
                    focused: $isSearchFocused,
                    textInputAutocapitalization: .words
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                content
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Constants.Surface)
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconButton(systemName: "xmark") {
                        isPresented = false
                    }
                }.sharedBackgroundHiddenCompat()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            isSearchFocused = true
            await service.fetchSuggestedLocationResults()
        }
        .task(id: searchText) {
            guard trimmedSearchText.count >= 2 else {
                await service.fetchLocationResults(search: trimmedSearchText)
                return
            }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await service.fetchLocationResults(search: trimmedSearchText)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if trimmedSearchText.isEmpty {
            suggestedContent
        } else if trimmedSearchText.count < 2 {
            emptyView("Keep typing")
        } else if service.isLoadingResults {
            loadingView()
        } else if let error = service.searchError,
            service.locationResults.isEmpty
        {
            errorView(error) {
                Task {
                    await service.fetchLocationResults(
                        search: trimmedSearchText
                    )
                }
            }
        } else if service.locationResults.isEmpty {
            emptyView("No locations found")
        } else {
            resultList
        }
    }

    @ViewBuilder
    private var suggestedContent: some View {
        if let error = service.suggestedError,
            service.suggestedLocationResults.isEmpty
        {
            errorView(error) {
                Task { await service.fetchSuggestedLocationResults() }
            }
        } else if service.suggestedLocationResults.isEmpty {
            emptyView("Search for a city")
        } else {
            resultList(service.suggestedLocationResults)
        }
    }

    private var resultList: some View {
        resultList(service.locationResults)
    }

    private func resultList(_ results: [LocationSearchResultDto]) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(results.indices, id: \.self) { index in
                    Button {
                        selectResult(results[index])
                    } label: {
                        locationRow(results[index])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .simultaneousGesture(
            DragGesture(minimumDistance: 1).onChanged { _ in
                if isSearchFocused {
                    isSearchFocused = false
                }
            }
        )
    }

    private func locationRow(_ result: LocationSearchResultDto) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(result.country.emoji ?? "")
                .font(.system(size: 30))
                .frame(width: 56, height: 56)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Constants.Neutral50)
                        .shadow(
                            color: Constants.Black.opacity(0.12),
                            radius: 10,
                            x: 0,
                            y: 5
                        )
                        .shadow(
                            color: Constants.Black.opacity(0.04),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                            .stroke(
                                Constants.Black.opacity(0.08),
                                lineWidth: 1.2
                            )
                        }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(city(for: result)?.name ?? result.state.name))
                    .font(Font.beVietnamPro(18))
                    .foregroundStyle(.black)
                    .lineLimit(1)

                Text(displayName(subtitle(for: result)))
                    .font(Font.beVietnamPro(16))
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func subtitle(for result: LocationSearchResultDto) -> String {
        if city(for: result) != nil {
            return "\(result.state.name), \(result.country.name)"
        }

        return result.country.name
    }

    private func city(for result: LocationSearchResultDto) -> CityDto? {
        result.city?.value1
    }

    private func displayName(_ name: String) -> String {
        name.localizedCapitalized
    }

    // MARK: - Shared Views

    private func loadingView() -> some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String, retry: @escaping () -> Void)
        -> some View
    {
        VStack(spacing: 12) {
            Spacer()
            Text(message)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
            Button("Retry") {
                retry()
            }
            .font(Font.beVietnamPro(14, weight: .medium))
            .foregroundColor(Constants.BlueBase)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func selectResult(_ result: LocationSearchResultDto) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onLocationSelected(city(for: result), result.state, result.country)
        isPresented = false
    }
}
