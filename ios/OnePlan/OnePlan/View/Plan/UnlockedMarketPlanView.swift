//
//  UnlockedMarketPlanView.swift
//  OnePlan
//
//  Created by ken on 10/4/26.
//

import SwiftUI

struct UnlockedMarketPlanView: View {
    private let staticItems: [AcquiredPlanItem]
    private let acquisitionsService: MyAcquisitionsService?

    init(acquisitions: [AcquiredPlanItem] = []) {
        self.staticItems = acquisitions
        self.acquisitionsService = nil
    }

    init(acquisitionsService: MyAcquisitionsService) {
        self.staticItems = []
        self.acquisitionsService = acquisitionsService
    }

    private var unlockedItems: [AcquiredPlanItem] {
        acquisitionsService?.acquisitions ?? staticItems
    }

    private var isLoadingInitialFeed: Bool {
        guard let acquisitionsService else { return false }
        return acquisitionsService.isLoading && acquisitionsService.acquisitions.isEmpty
    }

    private var shouldShowEmptyState: Bool {
        unlockedItems.isEmpty
    }

    var body: some View {
        Group {
            if isLoadingInitialFeed {
                loadingContent
            } else if shouldShowEmptyState {
                emptyStateContent
            } else {
                unlockedPlansContent
            }
        }
        .task {
            guard let acquisitionsService else { return }
            await acquisitionsService.loadAcquisitions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketplacePlanAcquired)) { _ in
            guard let acquisitionsService else { return }
            Task { await acquisitionsService.loadAcquisitions(force: true) }
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, 16)
        .background {
            ZStack(alignment: .top) {
                Color(Constants.Background)
                    .ignoresSafeArea()

                topBlurBackground
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .background(Constants.Background)
    }

    private var loadingContent: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Plan")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)

            Text("No unlocked plans yet")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var unlockedPlansContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Plan")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)

                VStack(spacing: 8) {
                    ForEach(unlockedItems) { item in
                        let card = MarketplaceItem(
                            creatorName: item.creatorName,
                            isCreatorVerified: false,
                            unlockText: String(localized: "Unlocked"),
                            isAcquired: true,
                            title: item.name,
                            activitiesText: activityText(for: item),
                            durationText: durationText(for: item),
                            priceText: item.priceText,
                            tags: item.tags,
                            avatarUrl: item.creatorAvatarUrl,
                            thumbnailUrl: item.coverImageUrl
                        )

                        if let listingId = item.listingId, item.listingStillAvailable {
                            NavigationLink {
                                MarketItemDetailView(listingId: listingId)
                            } label: {
                                card
                            }
                            .buttonStyle(.plain)
                        } else {
                            card
                        }
                    }
                }
            }
        }
    }

    // Both pluralized in the String Catalog by the count argument.
    private func durationText(for item: AcquiredPlanItem) -> String {
        String(localized: "\(max(item.durationDays, 1)) days")
    }

    private func activityText(for item: AcquiredPlanItem) -> String {
        String(localized: "\(max(item.activityCount, 0)) activities")
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 435, height: 455)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }
}

#Preview {
    UnlockedMarketPlanView(acquisitions: [])
}
