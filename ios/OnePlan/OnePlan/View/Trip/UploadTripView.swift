//
//  UploadTripView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct UploadTripView: View {
    private enum Route {
        case create(service: TripDetailService)
        case createFromTrip(service: TripDetailService, tripId: Int)
        case edit(listingId: Int)
    }

    private let route: Route

    init(service: TripDetailService) {
        self.route = .create(service: service)
    }

    init(service: TripDetailService, tripId: Int) {
        self.route = .createFromTrip(service: service, tripId: tripId)
    }

    init(listingId: Int) {
        self.route = .edit(listingId: listingId)
    }

    var body: some View {
        switch route {
        case let .create(service):
            CreateUploadTripView(service: service, tripId: nil)
        case let .createFromTrip(service, tripId):
            CreateUploadTripView(service: service, tripId: tripId)
        case let .edit(listingId):
            EditUploadTripView(listingId: listingId)
        }
    }
}

#Preview {
    NavigationStack {
        UploadTripView(service: TripDetailService(), tripId: 1)
    }
}
