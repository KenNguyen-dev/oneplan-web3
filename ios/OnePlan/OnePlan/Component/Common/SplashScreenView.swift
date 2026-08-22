//
//  SplashScreenView.swift
//  OnePlan
//

import SwiftUI

struct SplashScreenView: View {
    var onComplete: () -> Void

    // MARK: - Animation State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scaleDown = false
    @State private var scaleUp = false
    @State private var dismissed = false

    // MARK: - Config

    private let initialDelay: Double = 0.35
    private let backgroundColor: Color = .black
    private let logoBackgroundColor: Color = .white
    private let scaling: CGFloat = 4
    private let blurRadius: CGFloat = 15
    private let scaleUpDelay: Double = 0.1
    private let scaleUpAnimation: Animation = .smooth(duration: 1, extraBounce: 0)

    var body: some View {
        if reduceMotion {
            ZStack {
                Rectangle().fill(backgroundColor)
                Image("appLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
            }
            .ignoresSafeArea()
            .opacity(dismissed ? 0 : 1)
            .task {
                try? await Task.sleep(for: .seconds(initialDelay))
                withAnimation(.easeOut(duration: 0.5), completionCriteria: .logicallyComplete) {
                    dismissed = true
                } completion: {
                    onComplete()
                }
            }
        } else {
            Rectangle()
                .fill(backgroundColor)
                .mask {
                    GeometryReader { geo in
                        let size = geo.size.applying(
                            .init(scaleX: scaling, y: scaling)
                        )

                        Rectangle()
                            .overlay {
                                Image("appLogoCutout")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 32))
                                    .blur(radius: scaleUp ? blurRadius : 0)
                                    .blendMode(.destinationOut)
                                    .animation(
                                        .smooth(duration: 0.3, extraBounce: 0)
                                    ) { content in
                                        content
                                            .scaleEffect(scaleDown ? 0.8 : 1)
                                    }
                                    .visualEffect { [scaleUp] content, proxy in
                                        let scaleX = size.width / proxy.size.width
                                        let scaleY = size.height / proxy.size.height
                                        let maxScale = Swift.max(scaleX, scaleY)

                                        return content
                                            .scaleEffect(scaleUp ? maxScale : 1)
                                    }
                            }
                    }
                }
                .compositingGroup()
                .opacity(scaleUp ? 0 : 1)
                .background {
                    Rectangle()
                        .fill(logoBackgroundColor)
                        .opacity(scaleUp ? 0 : 1)
                }
                .ignoresSafeArea()
                .task {
                    guard !scaleDown else { return }
                    try? await Task.sleep(for: .seconds(initialDelay))
                    scaleDown = true
                    try? await Task.sleep(for: .seconds(scaleUpDelay))
                    withAnimation(scaleUpAnimation, completionCriteria: .logicallyComplete) {
                        scaleUp = true
                    } completion: {
                        onComplete()
                    }
                }
        }
    }
}

#Preview {
    SplashScreenView(onComplete: {})
}
