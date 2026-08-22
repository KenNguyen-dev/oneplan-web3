//
//  CreateGroupView.swift
//  OnePlan
//
//  Created by ken on 27/2/26.
//

import PhotosUI
import SwiftUI

struct CreateTripView: View {
    @Environment(StoreManager.self) private var storeManager
    @State private var showLocationPicker = false
    @State private var selectedLocationText: String?
    @State private var selectedCity: CityDto?
    @State private var selectedState: StateDto?
    @State private var selectedCountry: CountryDto?

    @State private var tripName: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var tripService = TripService()
    @State private var friendService = FriendService()
    @State private var storageService = StorageUploadService()
    @State private var selectedFriendIds: Set<Int> = []
    @State private var isCreating = false
    @State private var isShowingInviteWarning = false
    @State private var inviteWarningMessage = ""
    @State private var showingTripLimitPaywall = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTripNameFocused: Bool

    private var friendEntries: [FriendListEntry] {
        friendService.friends.map { friend in
            FriendListEntry(
                id: "\(friend.user.id)",
                name: friend.user.displayName,
                subtitleText: "\(friend.mutualFriendCount) mutual friends",
                avatarUrl: friend.user.avatarUrl,
                trailingAction: selectedFriendIds.contains(friend.user.id) ? .sent : .invite,
                isPro: friend.user.isPro
            )
        }
    }

    private var displayedFriendEntries: [FriendListEntry] {
        Array(friendEntries.prefix(5))
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()

            // Cover image picker
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(
                            color: Color(red: 0.2, green: 0.36, blue: 1).opacity(0.2),
                            radius: 11.8, x: 0, y: 0
                        )
                } else {
                    VStack(alignment: .center, spacing: 20) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .center, spacing: 10) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 24))
                                    .foregroundColor(Constants.BlueBase)
                            }
                            .padding(2)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .center
                            )
                            .background(.white)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .inset(by: 0.5)
                                    .stroke(
                                        .black.opacity(0.25),
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                                    )
                            )
                        }
                        .padding(4)
                        .frame(height: 72, alignment: .topLeading)
                        .background(.white)
                        .cornerRadius(20)
                        .shadow(
                            color: Color(red: 0.2, green: 0.36, blue: 1).opacity(0.2),
                            radius: 11.8,
                            x: 0,
                            y: 0
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .inset(by: 0.24)
                                .stroke(.black.opacity(0.15), lineWidth: 0.48881)
                        )
                    }
                    .padding(0)
                    .frame(maxWidth: 72, maxHeight: 72, alignment: .top)
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

            TextField("Trip name", text: $tripName)
                .font(Font.custom("Be Vietnam Pro", size: 24))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .focused($isTripNameFocused)
                .textFieldStyle(.plain)

            Spacer()

            Button {
                isTripNameFocused = false
                showLocationPicker = true
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .padding(0)
                        .font(.system(size: 16))
                        .foregroundColor(Constants.BlueBase)

                    Text(selectedLocationText ?? "Choose trip location")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(
                            selectedLocationText != nil
                                ? Constants.ContentB
                                : Constants.ContentM
                        )
                        .lineLimit(1)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Constants.Surface)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                if friendEntries.isEmpty {
                    VStack(spacing: 14) {
                        Image("emptyFriend")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 134.8, height: 160)

                        Text("You don’t have any friend.")
                            .font(Font.beVietnamPro(16, weight: .medium))
                            .tracking(-0.64)
                            .foregroundColor(Constants.ContentM)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("\(friendService.friends.count) friends")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundColor(Constants.ContentM)

                            Spacer()

                            NavigationLink {
                                FriendsListView(selectedFriendIds: $selectedFriendIds)
                            } label: {
                                Text("See All")
                                    .font(
                                        Font.beVietnamPro(14, weight: .medium)
                                    )
                                    .foregroundColor(Constants.BlueBase)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    FriendList(
                        entries: displayedFriendEntries,
                        onTrailingActionTapped: { entry in
                            guard let userId = Int(entry.id) else { return }
                            selectedFriendIds.insert(userId)
                        }
                    )
                }

                PrimaryButton(title: isCreating ? "Creating..." : "Create Trip") {
                    createTrip()
                }
                .disabled(isCreating || tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCountry == nil)
                .padding(.horizontal, 16)

                if let error = tripService.error {
                    Text(error)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.Warning500)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Constants.Surface)
            .cornerRadius(24)
        }
        
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await friendService.loadFriends()
        }
        .fullScreenCover(isPresented: $showLocationPicker) {
            TripLocationPickerSheet(
                isPresented: $showLocationPicker
            ) { city, state, country in
                selectedCity = city
                selectedState = state
                selectedCountry = country
                if let city {
                    selectedLocationText = "\(city.name), \(state.name), \(country.name)"
                } else {
                    selectedLocationText = "\(state.name), \(country.name)"
                }
            }
        }
        .alert("Trip created with warnings", isPresented: $isShowingInviteWarning) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(inviteWarningMessage)
        }
        .sheet(isPresented: $showingTripLimitPaywall) {
            SubscriptionView()
        }
        .background(Constants.Background)
        .ignoresSafeArea(.keyboard)
    }

    private func createTrip() {
        let name = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            isCreating = true
            defer { isCreating = false }
            tripService.error = nil

            if !storeManager.isPro {
                await tripService.listMyTrips(force: true)

                guard tripService.canCreatePlanningTrip(isPro: storeManager.isPro) else {
                    tripService.error =
                        String(localized: "Free users can only have up to \(TripService.nonPremiumPlanningTripLimit) planning trips.", comment: "%lld = max planning trips for free users")
                    showingTripLimitPaywall = true
                    return
                }
            }

            do {
                let trip = try await tripService.createTrip(
                    name: name,
                    cityId: selectedCity.map { $0.id },
                    stateId: selectedState.map { $0.id },
                    countryId: selectedCountry.map { $0.id }
                )

                // Upload cover image if selected (non-blocking — trip is already created)
                if let image = selectedImage {
                    do {
                        _ = try await storageService.uploadImage(
                            image,
                            target: .trip_hyphen_cover,
                            entityId: Int(trip.id)
                        )
                    } catch {
                        print("Cover image upload failed: \(error)")
                    }
                }

                var inviteWarning: String?
                if !selectedFriendIds.isEmpty {
                    do {
                        try await tripService.inviteMembers(
                            tripId: Int(trip.id),
                            userIds: selectedFriendIds.sorted()
                        )
                    } catch {
                        inviteWarningMessage =
                            String(localized: "Trip was created, but we couldn't send all selected invites. You can invite friends from the trip details.", comment: "Warning after trip creation when some invites failed")
                        inviteWarning = inviteWarningMessage
                    }
                }

                NotificationCenter.default.post(
                    name: .tripCreated,
                    object: nil,
                    userInfo: ["tripId": trip.id]
                )

                if inviteWarning != nil {
                    isShowingInviteWarning = true
                } else {
                    dismiss()
                }
            } catch {
                // tripService.error is already set
            }
        }
    }
}

#Preview {
    CreateTripView()
        .environment(UserProfileService())
        .background(Constants.Background.ignoresSafeArea())
}
