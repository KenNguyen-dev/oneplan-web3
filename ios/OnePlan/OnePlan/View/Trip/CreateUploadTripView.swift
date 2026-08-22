//
//  CreateUploadTripView.swift
//  OnePlan
//

import SwiftUI

struct CreateUploadTripView: View {
    let service: TripDetailService
    let tripId: Int?

    // This is an intermediate pushed host (reads dismiss + hosts an onward
    // navigationDestination). On iOS < 26 reading `@Environment(\.dismiss)`
    // directly feeds the action-env relayout loop that freezes the form when a
    // child push ("New Plan") mounts. Route dismiss through StableDismiss so the
    // body never re-renders on dismiss-identity churn.
    @State private var stableDismiss = StableDismiss()
    @State private var isShowingPlanBeingVerified = false

    var body: some View {
        UploadTripFormView(
            mode: .create(service: service, tripId: tripId),
            onClose: { stableDismiss() },
            onPublishSuccess: { success in
                guard case .created = success else { return }
                isShowingPlanBeingVerified = true
            }
        )
        .captureStableDismiss(stableDismiss)
        .navigationDestination(isPresented: $isShowingPlanBeingVerified) {
            TripBeingVerifiedView()
                .navigationBarBackButtonHidden(true)
        }
    }
}
