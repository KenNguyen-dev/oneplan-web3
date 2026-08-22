//
//  PioneerAvatar.swift
//  OnePlan
//
//  Created by ken on 24/2/26.
//

import SwiftUI

struct PioneerAvatar: View {
    var size: CGFloat = 220
    var imageUrl: String? = nil
    private let duration: Double = 38.2
    @State private var startTime: Date = .now

    var body: some View {
        let shape = PioneerAvatarShape()

        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let progress = (elapsed / duration).truncatingRemainder(dividingBy: 1)
            let rotation = progress * 360

            ZStack {
                Group {
                    if let imageUrl, let url = URL(string: imageUrl) {
                        CachedRemoteImage(
                            url: url,
                            targetSize: CGSize(width: size, height: size)
                        ) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image("defaultTripPlaceholder")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    } else {
                        Image("defaultTripPlaceholder")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: size, height: size)
                .mask(
                    shape
                        .rotationEffect(.degrees(rotation))
                )

                shape
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            startTime = .now
        }
    }
}

struct PioneerAvatarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let minSide = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = (minSide / 2) * 0.905
        let points = 280

        var path = Path()

        for i in 0...points {
            let t = CGFloat(i) / CGFloat(points)
            let angle = t * .pi * 2
            // Fixed offsets keep the silhouette rigid while allowing visible rotation.
            let w1 = sin(12 * angle + 0.35) * 0.055
            let w2 = sin(7 * angle + 1.4) * 0.018
            let w3 = sin(3 * angle - 0.8) * 0.012
            let radius = baseRadius * (1 + w1 + w2 + w3)
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color(red: 0.86, green: 0.88, blue: 0.92).ignoresSafeArea()
        PioneerAvatar(size: 280)
    }
}

#Preview("Remote Image") {
    ZStack {
        Color(red: 0.86, green: 0.88, blue: 0.92).ignoresSafeArea()
        PioneerAvatar(
            size: 280,
            imageUrl:
                "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=600"
        )
    }
}
