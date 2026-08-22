import MapKit
import SwiftUI

enum LocationDirectionsTransportMode: CaseIterable {
    case driving
    case walking

    var iconName: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.run"
        }
    }

    var paceMetersPerMinute: Double {
        switch self {
        case .walking: return 5_000.0 / 60.0
        case .driving: return 30_000.0 / 60.0
        }
    }

    var travelLabel: String {
        switch self {
        case .walking: return String(localized: "by foot", comment: "Travel mode in directions")
        case .driving: return String(localized: "by car", comment: "Travel mode in directions")
        }
    }

    var mapsLaunchMode: String {
        switch self {
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .driving: return MKLaunchOptionsDirectionsModeDriving
        }
    }

    var googleMapsTravelMode: String {
        switch self {
        case .walking: return "walking"
        case .driving: return "driving"
        }
    }
}

struct LocationDirectionsTopLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white))
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
    }
}

struct LocationDirectionsControlBar: View {
    let selectedMode: LocationDirectionsTransportMode
    let travelMinutes: Int
    let onCollapse: () -> Void
    let onSelectMode: (LocationDirectionsTransportMode) -> Void
    let onOpenInAppleMaps: () -> Void
    let onOpenInGoogleMaps: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            routeStrip

            VStack(alignment: .leading, spacing: 6) {
                Text("Direction")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.28)
                    .padding(.top, 4)
                    .padding(.horizontal, 4)

                HStack(spacing: 8) {
                    directionButton(
                        title: "Apple map",
                        icon: {
                            Image("appleMap")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipped()
                        },
                        action: onOpenInAppleMaps
                    )

                    directionButton(
                        title: "Google map",
                        icon: {
                            Image("googleMaps")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 23, height: 23)
                                .clipped()
                        },
                        action: onOpenInGoogleMaps
                    )
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Neutral50)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 36))
    }

    private var routeStrip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.85, green: 0.92, blue: 1))
                    .frame(height: 30)
                    .overlay {
                        DiagonalRouteStripes()
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .frame(height: 30)
                    }

                Text(routeText)
                    .font(Font.beVietnamPro(14, weight: .medium))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.28)
                    .frame(width: max(0, width - 129), alignment: .center)
                    .offset(x: 97)

                HStack(spacing: 0) {
                    ForEach([LocationDirectionsTransportMode.driving, .walking], id: \.self) { mode in
                        modeSegment(mode)
                    }
                }
                .frame(width: 97, height: 32)
                .background(Constants.White)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Constants.BlueBase, lineWidth: 2)
                )

                Button(action: onCollapse) {
                    Circle()
                        .fill(Constants.White)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Constants.BlueBase, lineWidth: 2)
                                .padding(2)
                        )
                        .overlay(
                            Circle()
                                .fill(Color(red: 0.38, green: 0.55, blue: 1))
                                .frame(width: 22, height: 22)
                        )
                }
                .buttonStyle(.plain)
                .position(x: width - 16, y: 16)
            }
        }
        .frame(height: 32)
    }

    private var routeText: AttributedString {
        var minutes = AttributedString("\(travelMinutes) mins")
        minutes.font = .beVietnamPro(14, weight: .semibold)
        minutes.foregroundColor = Constants.BlueBase

        var mode = AttributedString(" \(selectedMode.travelLabel)")
        mode.font = .beVietnamPro(14, weight: .medium)
        mode.foregroundColor = Constants.ContentB

        minutes.append(mode)
        return minutes
    }

    private func modeSegment(_ mode: LocationDirectionsTransportMode) -> some View {
        let isSelected = mode == selectedMode

        return Button(action: { onSelectMode(mode) }) {
            Image(systemName: mode.iconName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isSelected ? Constants.White : Constants.ContentM)
                .frame(width: 48.5, height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? Constants.BlueBase : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func directionButton<Icon: View>(
        title: LocalizedStringKey,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                    .frame(width: 23, height: 23)

                Text(title)
                    .font(Font.custom("Be Vietnam Pro", size: 15))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Constants.White)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct LocationDirectionsInfoCard: View {
    let travelMinutes: Int
    let transportMode: LocationDirectionsTransportMode
    let distanceText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(travelMinutes) min \(transportMode.travelLabel)")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.black)

            Text("You are \(distanceText) away")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

#Preview("DirectionsControlBar") {
    LocationDirectionsControlBar(
        selectedMode: .walking,
        travelMinutes: 3,
        onCollapse: {},
        onSelectMode: { _ in },
        onOpenInAppleMaps: {},
        onOpenInGoogleMaps: {}
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("DirectionsInfoCard") {
    LocationDirectionsInfoCard(
        travelMinutes: 8,
        transportMode: .walking,
        distanceText: "691 m"
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}

private struct DiagonalRouteStripes: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let count = Int(proxy.size.width / 20) + 4

            HStack(spacing: 11) {
                ForEach(0..<count, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(red: 0.8, green: 0.89, blue: 1))
                        .frame(width: 9, height: 74)
                        .rotationEffect(.degrees(43))
                }
            }
            .offset(x: -44 + phase, y: -25)
            .onAppear {
                guard !reduceMotion else { return }
                phase = 0
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 20
                }
            }
        }
    }
}

#Preview("DirectionsTopLabel") {
    LocationDirectionsTopLabel(
        title: "Jollibee Tô Hiến Thành",
        subtitle: "Recently viewed"
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}
