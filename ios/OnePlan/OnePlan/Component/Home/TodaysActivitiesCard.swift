//
//  TodaysActivitiesCard.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//
//  "Today's activities" card on Home (Figma 3823:17553): header row with
//  signpost illustration, pin count and a "View details" action, above a
//  non-interactive map preview of today's plan-item pins with the driving
//  route. Adapted from TripPlanSection's planOverviewCard.
//

import MapKit
import SwiftUI

struct TodaysActivitiesCard: View {
    let pins: [PlanDayPin]
    let onViewDetails: () -> Void

    @State private var routeLegs: [PlanDayRouteLeg] = []

    var body: some View {
        Button(action: onViewDetails) {
            VStack(spacing: 8) {
                headerRow
                mapPreview
            }
            .padding(8)
            .background(Constants.Surface)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.06), radius: 8.95, x: 0, y: 0)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image("signpost")
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Today’s activities")
                    .font(.beVietnamPro(16))
                    .tracking(-0.32)
                    .foregroundStyle(Constants.ContentB)
                Text("\(pins.count) pins")
                    .font(.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
            }

            Spacer(minLength: 8)

            Text("View details")
                .font(.beVietnamPro(15, weight: .medium))
                .foregroundStyle(Constants.White)
                .padding(.horizontal, 20)
                .frame(height: 42)
                .background(Constants.BlueBase)
                .clipShape(Capsule())
        }
    }

    private var mapPreview: some View {
        Map(
            position: .constant(.region(PlanDayPin.fittedRegion(for: pins))),
            interactionModes: []
        ) {
            // No straight-line placeholder: the route appears only once the
            // driving legs are loaded, so it never visibly re-shapes.
            ForEach(Array(routeLegs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(leg.polyline)
                    .stroke(
                        Constants.BlueBase,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate, anchor: .center) {
                    PlanDayNumberMarker(index: pin.index)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .task(id: pins.map(\.id)) {
            routeLegs = []
            routeLegs = await PlanDayPin.drivingRouteLegs(for: pins)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 183)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ZStack {
        Constants.Background.ignoresSafeArea()
        TodaysActivitiesCard(
            pins: [
                PlanDayPin(
                    id: 1,
                    index: 1,
                    title: "Morning Coffee",
                    coordinate: CLLocationCoordinate2D(latitude: 16.0678, longitude: 108.2208)
                ),
                PlanDayPin(
                    id: 2,
                    index: 2,
                    title: "Dragon Bridge",
                    coordinate: CLLocationCoordinate2D(latitude: 16.0614, longitude: 108.2277)
                ),
            ],
            onViewDetails: {}
        )
        .padding(16)
    }
}
