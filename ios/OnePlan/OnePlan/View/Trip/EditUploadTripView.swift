//
//  EditUploadTripView.swift
//  OnePlan
//

import SwiftUI

struct EditUploadTripView: View {
    let listingId: Int

    // Intermediate pushed host (reads dismiss + hosts an onward
    // navigationDestination). On iOS < 26 reading `@Environment(\.dismiss)`
    // directly feeds the action-env relayout loop that freezes the form when a
    // child push ("New Plan") mounts. Route dismiss through StableDismiss so the
    // body never re-renders on dismiss-identity churn.
    @State private var stableDismiss = StableDismiss()
    @State private var isShowingPlanBeingVerified = false

    var body: some View {
        UploadTripFormView(
            mode: .edit(listingId: listingId),
            onClose: { stableDismiss() },
            onPublishSuccess: { success in
                guard case let .updated(info) = success else { return }
                NotificationCenter.default.post(name: .listingUpdated, object: info)
                isShowingPlanBeingVerified = true
            },
            onDeleteSuccess: {
                NotificationCenter.default.post(name: .listingUpdated, object: nil)
                stableDismiss()
            }
        )
        .captureStableDismiss(stableDismiss)
        .navigationDestination(isPresented: $isShowingPlanBeingVerified) {
            TripBeingVerifiedView()
                .navigationBarBackButtonHidden(true)
        }
    }
}
