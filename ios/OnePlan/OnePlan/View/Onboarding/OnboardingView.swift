//
//  OnboardingView.swift
//  OnePlan
//
//  Adapted from iOS26StyleOnBoarding by Balaji Venkatesh
//

import SwiftUI

struct OnboardingView: View {
    var tint: Color = .blue
    var hideBezels: Bool = false
    var items: [OnboardingItem] = OnboardingItem.defaultItems
    var onComplete: () -> Void

    @State private var currentIndex: Int = 0
    @State private var screenshotSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ScreenshotView()
                .compositingGroup()
                .scaleEffect(
                    items[currentIndex].zoomScale,
                    anchor: items[currentIndex].zoomAnchor
                )
                .padding(.top, 35)
                .padding(.horizontal, 30)
                .padding(.bottom, 220)

            VStack(spacing: 10) {
                TextContentView()
                IndicatorView()
                ContinueButton()
            }
            .padding(.top, 20)
            .padding(.horizontal, 15)
            .frame(height: 210)
            .background {
                VariableGlassBlur(15)
            }

            BackButton()
        }
        .preferredColorScheme(.dark)
    }

    /// Screenshot View
    @ViewBuilder
    func ScreenshotView() -> some View {
        GeometryReader {
            let size = $0.size

            Rectangle()
                .fill(.black)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]

                        Image(item.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .onGeometryChange(for: CGSize.self) {
                                $0.size
                            } action: { newValue in
                                guard index == 0 && screenshotSize == .zero else { return }
                                screenshotSize = newValue
                            }
                            .clipShape(RoundedRectangle(cornerRadius: deviceCornerRadius))
                            .frame(width: size.width, height: size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: Binding<Int?>(
                get: { currentIndex },
                set: { _ in }
            ))
        }
        .clipShape(RoundedRectangle(cornerRadius: deviceCornerRadius))
        .overlay {
            if screenshotSize != .zero && !hideBezels {
                /// Device Frame UI
                ZStack {
                    RoundedRectangle(cornerRadius: deviceCornerRadius)
                        .stroke(.white, lineWidth: 6)

                    RoundedRectangle(cornerRadius: deviceCornerRadius)
                        .stroke(.black, lineWidth: 4)

                    RoundedRectangle(cornerRadius: deviceCornerRadius)
                        .stroke(.black, lineWidth: 6)
                        .padding(4)
                }
                .padding(-7)
            }
        }
        .frame(
            maxWidth: screenshotSize.width == 0 ? nil : screenshotSize.width,
            maxHeight: screenshotSize.height == 0 ? nil : screenshotSize.height
        )
        .containerShape(RoundedRectangle(cornerRadius: deviceCornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Text Content View
    @ViewBuilder
    func TextContentView() -> some View {
        GeometryReader {
            let size = $0.size

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        let isActive = currentIndex == index

                        VStack(spacing: 6) {
                            Text(item.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundStyle(.white)

                            Text(item.subtitle)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: size.width)
                        .compositingGroup()
                        /// Only The current Item is visible others are blurred out!
                        .blur(radius: isActive ? 0 : 30)
                        .opacity(isActive ? 1 : 0)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .scrollTargetBehavior(.paging)
            .scrollClipDisabled()
            .scrollPosition(id: Binding<Int?>(
                get: { currentIndex },
                set: { _ in }
            ))
        }
    }

    /// Indicator View
    @ViewBuilder
    func IndicatorView() -> some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let isActive: Bool = currentIndex == index

                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.4))
                    .frame(width: isActive ? 25 : 6, height: 6)
            }
        }
        .padding(.bottom, 5)
    }

    /// Bottom Continue Button
    @ViewBuilder
    func ContinueButton() -> some View {
        // Literals bind to the `LocalizedStringKey` parameter, so both keys are
        // still extracted to the String Catalog and localized.
        PrimaryButton(
            title: currentIndex == items.count - 1 ? "Get Started" : "Continue"
        ) {
            if currentIndex == items.count - 1 {
                onComplete()
            }

            withAnimation(animation) {
                currentIndex = min(currentIndex + 1, items.count - 1)
            }
        }
        .padding(.horizontal, 30)
    }

    /// Back Button
    @ViewBuilder
    func BackButton() -> some View {
        if currentIndex > 0 {
            Button {
                withAnimation(animation) {
                    currentIndex = max(currentIndex - 1, 0)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 20, height: 30)
            }
            .modifier(BackButtonStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 15)
            .padding(.top, 5)
        }
    }

    /// Variable Glass Effect Blur
    @ViewBuilder
    func VariableGlassBlur(_ radius: CGFloat) -> some View {
        let isZoomed = items[currentIndex].zoomScale > 1
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .modifier(GlassBlurModifier())
            .blur(radius: radius)
            .padding(.horizontal, -radius * 2)
            .padding(.bottom, -radius * 2)
            .padding(.top, -radius / 2)
            .opacity(isZoomed ? 1 : 0)
            .ignoresSafeArea()
    }

    var deviceCornerRadius: CGFloat {
        /// Using a fixed corner radius since we're using asset images
        /// Adjust this value based on your screenshot aspect ratio
        let ratio = screenshotSize.height / 844 // iPhone 14 Pro height
        let actualCornerRadius: CGFloat = 55
        return screenshotSize.height == 0 ? 55 : actualCornerRadius * ratio
    }

    /// Customize it according to your needs!
    var animation: Animation {
        .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }
}

// MARK: - Button Style Modifiers

private struct BackButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
        }
    }
}

private struct GlassBlurModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.clear, in: .rect)
        } else {
            content
        }
    }
}

#Preview {
    OnboardingView {
        print("Completed")
    }
}
