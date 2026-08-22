import SwiftUI

struct LocationCompassWidget: View {
    let distanceText: String
    let bearingDegrees: Double
    let deviceHeadingDegrees: Double
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                CompassFace(rotationDegrees: bearingDegrees - deviceHeadingDegrees)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 0) {
                    Text(distanceText)
                        .font(Font.beVietnamPro(15, weight: .heavy))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.3)

                    Text("From you")
                        .font(Font.custom("Be Vietnam Pro", size: 10))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.2)
                }
                .lineSpacing(0)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CompassFace: View {
    let rotationDegrees: Double

    private let tickCount = 12

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2

            ZStack {
                ForEach(0..<tickCount, id: \.self) { index in
                    let isCardinal = index % 3 == 0
                    Capsule()
                        .fill(isCardinal ? Constants.ContentB.opacity(0.8) : Constants.ContentM.opacity(0.45))
                        .frame(
                            width: isCardinal ? 1.4 : 1,
                            height: isCardinal ? 5 : 3
                        )
                        .offset(y: -(radius - (isCardinal ? 3 : 2)))
                        .rotationEffect(.degrees(Double(index) * (360.0 / Double(tickCount))))
                }

                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.blue)
                    .rotationEffect(.degrees(rotationDegrees))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview("LocationCompassWidget") {
    VStack(spacing: 16) {
        LocationCompassWidget(
            distanceText: "564 m",
            bearingDegrees: 45,
            deviceHeadingDegrees: 0
        )

        LocationCompassWidget(
            distanceText: "2.3 km",
            bearingDegrees: 180,
            deviceHeadingDegrees: 0
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
