//
//  PlanDayMapView.swift
//  OnePlan
//

import CoreLocation
import MapKit
import SwiftUI

struct PlanDayPin: Identifiable {
    let id: Int
    let index: Int
    let title: String
    let coordinate: CLLocationCoordinate2D
    var subtitle: String? = nil
    var timeLabel: String? = nil

    /// Driving-route legs between consecutive pins. Failed legs (no drivable
    /// route, network error) fall back to a straight segment with nil
    /// time/distance so the path never has visual gaps.
    static func drivingRouteLegs(for pins: [PlanDayPin]) async -> [PlanDayRouteLeg] {
        guard pins.count >= 2 else { return [] }
        return await withTaskGroup(of: (Int, PlanDayRouteLeg).self) { group in
            for index in 0..<(pins.count - 1) {
                let source = pins[index].coordinate
                let destination = pins[index + 1].coordinate
                group.addTask {
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
                    request.transportType = .automobile
                    if let route = try? await MKDirections(request: request).calculate().routes.first {
                        return (
                            index,
                            PlanDayRouteLeg(
                                polyline: route.polyline,
                                travelTime: route.expectedTravelTime,
                                distance: route.distance
                            )
                        )
                    }
                    var straight = [source, destination]
                    return (
                        index,
                        PlanDayRouteLeg(
                            polyline: MKPolyline(coordinates: &straight, count: 2),
                            travelTime: nil,
                            distance: nil
                        )
                    )
                }
            }
            var legs: [(Int, PlanDayRouteLeg)] = []
            for await leg in group {
                legs.append(leg)
            }
            return legs.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func fittedRegion(for pins: [PlanDayPin]) -> MKCoordinateRegion {
        guard let first = pins.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }

        var minLatitude = first.coordinate.latitude
        var maxLatitude = first.coordinate.latitude
        var minLongitude = first.coordinate.longitude
        var maxLongitude = first.coordinate.longitude
        for pin in pins.dropFirst() {
            minLatitude = min(minLatitude, pin.coordinate.latitude)
            maxLatitude = max(maxLatitude, pin.coordinate.latitude)
            minLongitude = min(minLongitude, pin.coordinate.longitude)
            maxLongitude = max(maxLongitude, pin.coordinate.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.4, 0.005),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.4, 0.005)
            )
        )
    }
}

struct PlanDayRouteLeg {
    let polyline: MKPolyline
    let travelTime: TimeInterval?
    let distance: CLLocationDistance?

    /// e.g. "12 min · 4.2 km"; nil for straight-line fallback legs.
    var infoText: String? {
        guard let travelTime, let distance else { return nil }
        let minutes = max(1, Int((travelTime / 60).rounded()))
        let kilometers = distance / 1_000
        let distanceText = kilometers < 10
            ? "\(kilometers.formatted(.number.precision(.fractionLength(1)))) km"
            : "\(Int(kilometers.rounded()).formatted()) km"
        return String(localized: "\(minutes) min · \(distanceText)")
    }
}

struct PlanDayNumberMarker: View {
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Constants.BlueBase)
            Circle()
                .strokeBorder(Constants.White, lineWidth: 2)
        }
        .frame(width: 29, height: 29)
        .overlay {
            Text("\(index)")
                .font(Font.beVietnamPro(14, weight: .semibold))
                .foregroundColor(Constants.White)
        }
    }
}

struct PlanDayMapView: View {
    private static let miniDetent = PresentationDetent.height(80)
    private static let expandedDetent = PresentationDetent.height(300)

    let dayLabel: String
    let pins: [PlanDayPin]

    @State private var cameraPosition: MapCameraPosition
    @State private var routeLegs: [PlanDayRouteLeg]
    @State private var selectedPinIndex: Int?
    @State private var isSheetPresented = false
    @State private var sheetDetent: PresentationDetent = PlanDayMapView.expandedDetent
    /// True while the camera is being moved by code (selection zoom, initial
    /// fit). Camera changes outside this window are user pans/zooms and
    /// collapse the sheet to the mini bar.
    @State private var isProgrammaticCameraMove = true

    init(dayLabel: String, pins: [PlanDayPin], routeLegs: [PlanDayRouteLeg] = []) {
        self.dayLabel = dayLabel
        self.pins = pins
        _routeLegs = State(initialValue: routeLegs)
        _cameraPosition = State(initialValue: .region(PlanDayPin.fittedRegion(for: pins)))
    }

    /// 0-based index of the leg to show for the selected pin: the outgoing
    /// leg (pin index p is 1-based → leg p-1). The last stop has no outgoing
    /// leg, so it falls back to its incoming one (p-2). Empty in overview.
    private var highlightedLegIndexes: Set<Int> {
        guard let selectedPinIndex else { return [] }
        let outgoing = selectedPinIndex - 1
        if (0..<routeLegs.count).contains(outgoing) {
            return [outgoing]
        }
        let incoming = selectedPinIndex - 2
        return (0..<routeLegs.count).contains(incoming) ? [incoming] : []
    }

    private func isLegHighlighted(_ index: Int) -> Bool {
        selectedPinIndex == nil || highlightedLegIndexes.contains(index)
    }

    private func selectPin(_ index: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedPinIndex = selectedPinIndex == index ? nil : index
        sheetDetent = Self.expandedDetent
    }

    private func beginProgrammaticCameraMove() {
        isProgrammaticCameraMove = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            isProgrammaticCameraMove = false
        }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            // Focus mode hides non-adjacent legs entirely so the selected
            // stop's route reads clearly. No straight-line placeholder: the
            // route appears only once the driving legs are loaded, so it
            // never visibly re-shapes.
            ForEach(Array(routeLegs.enumerated()), id: \.offset) { index, leg in
                if isLegHighlighted(index) {
                    MapPolyline(leg.polyline)
                        .stroke(
                            Constants.BlueBase,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }
            }

            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate, anchor: .center) {
                    Button {
                        selectPin(pin.index)
                    } label: {
                        PlanDayNumberMarker(index: pin.index)
                            .scaleEffect(selectedPinIndex == pin.index ? 1.15 : 1)
                            .animation(.snappy(duration: 0.2), value: selectedPinIndex)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .all))
        // Keep the fitted region inside the area visible above the bottom
        // sheet — without this the southernmost stops hide behind it.
        .safeAreaPadding(.bottom, 300)
        .task {
            guard routeLegs.isEmpty else { return }
            routeLegs = await PlanDayPin.drivingRouteLegs(for: pins)
        }
        .onMapCameraChange(frequency: .continuous) { _ in
            if !isProgrammaticCameraMove {
                sheetDetent = Self.miniDetent
            }
        }
        .onChange(of: selectedPinIndex) { _, newValue in
            beginProgrammaticCameraMove()
            withAnimation {
                if let newValue, let pin = pins.first(where: { $0.index == newValue }) {
                    // Frame the highlighted leg: selected stop + the next one
                    // (previous one for the last stop).
                    let partnerIndex = newValue < pins.count ? newValue + 1 : newValue - 1
                    let partner = pins.first(where: { $0.index == partnerIndex })
                    cameraPosition = .region(
                        PlanDayPin.fittedRegion(for: [pin, partner].compactMap { $0 })
                    )
                } else {
                    cameraPosition = .region(PlanDayPin.fittedRegion(for: pins))
                }
            }
        }
        .onAppear {
            isSheetPresented = true
            beginProgrammaticCameraMove()
        }
        .onDisappear { isSheetPresented = false }
        .sheet(isPresented: $isSheetPresented) {
            PlanDayStopListSheet(
                dayLabel: dayLabel,
                pins: pins,
                routeLegs: routeLegs,
                selectedPinIndex: $selectedPinIndex,
                isMinimized: sheetDetent == Self.miniDetent,
                onSelectPin: selectPin,
                onExpand: { sheetDetent = Self.expandedDetent }
            )
            .presentationDetents([Self.miniDetent, Self.expandedDetent], selection: $sheetDetent)
            .presentationBackgroundInteraction(.enabled(upThrough: Self.expandedDetent))
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
            .interactiveDismissDisabled()
        }
        .navigationTitle(dayLabel)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct PlanDayStopListSheet: View {
    let dayLabel: String
    let pins: [PlanDayPin]
    let routeLegs: [PlanDayRouteLeg]
    @Binding var selectedPinIndex: Int?
    let isMinimized: Bool
    let onSelectPin: (Int) -> Void
    let onExpand: () -> Void

    var body: some View {
        Group {
            if isMinimized {
                miniBar
            } else {
                expandedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Surface)
    }

    // MARK: - Mini bar (shown while the user explores the map)

    private var miniBar: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                if let focused = focusedPin {
                    PlanDayNumberMarker(index: focused.index)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(focused.title)
                            .font(Font.beVietnamPro(15, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                            .lineLimit(1)
                        if let subtitle = focused.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(Font.beVietnamPro(13))
                                .foregroundColor(Constants.ContentM)
                                .lineLimit(1)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(dayLabel) overview")
                            .font(Font.beVietnamPro(15, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                        Text("\(pins.count) stops")
                            .font(Font.beVietnamPro(13))
                            .foregroundColor(Constants.ContentM)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Constants.ContentM)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var focusedPin: PlanDayPin? {
        guard let selectedPinIndex else { return nil }
        return pins.first { $0.index == selectedPinIndex }
    }

    // MARK: - Expanded content (header + vertical stop list)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pins) { pin in
                            stopRow(for: pin)
                                .id(pin.index)

                            if pin.index < pins.count,
                               let info = legInfo(afterPinIndex: pin.index) {
                                legInfoRow(info)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedPinIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var header: some View {
        Button {
            selectedPinIndex = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(dayLabel) overview")
                    .font(Font.beVietnamPro(16, weight: .semibold))
                    .foregroundColor(Constants.ContentB)
                Text("\(pins.count) stops")
                    .font(Font.beVietnamPro(13))
                    .foregroundColor(Constants.ContentM)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stopRow(for pin: PlanDayPin) -> some View {
        Button {
            onSelectPin(pin.index)
        } label: {
            HStack(spacing: 12) {
                PlanDayNumberMarker(index: pin.index)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.title)
                        .font(Font.beVietnamPro(15, weight: .medium))
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)
                    if let subtitle = pin.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.beVietnamPro(13))
                            .foregroundColor(Constants.ContentM)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let timeLabel = pin.timeLabel {
                    Text(timeLabel)
                        .font(Font.beVietnamPro(13, weight: .medium))
                        .foregroundColor(Constants.ContentM)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                selectedPinIndex == pin.index ? Constants.BlueAlpha10 : Color.clear
            )
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legInfo(afterPinIndex pinIndex: Int) -> String? {
        let legIndex = pinIndex - 1
        guard (0..<routeLegs.count).contains(legIndex) else { return nil }
        return routeLegs[legIndex].infoText
    }

    private func legInfoRow(_ info: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Constants.ContentL.opacity(0.4))
                .frame(width: 1, height: 18)
                .padding(.leading, 24)
            Text(info)
                .font(Font.beVietnamPro(12))
                .foregroundColor(Constants.ContentM)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        PlanDayMapView(
            dayLabel: "Day 2",
            pins: [
                PlanDayPin(
                    id: 1,
                    index: 1,
                    title: "Midnight Check-in",
                    coordinate: CLLocationCoordinate2D(latitude: 11.9404, longitude: 108.4583),
                    subtitle: "Hotel Lobby",
                    timeLabel: "00:05"
                ),
                PlanDayPin(
                    id: 2,
                    index: 2,
                    title: "Morning Coffee",
                    coordinate: CLLocationCoordinate2D(latitude: 11.9466, longitude: 108.4419),
                    subtitle: "The Coffee House",
                    timeLabel: "08:00"
                ),
            ]
        )
    }
}
