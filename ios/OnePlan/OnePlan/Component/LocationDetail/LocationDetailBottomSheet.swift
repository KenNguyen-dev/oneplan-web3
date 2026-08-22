import SwiftUI

struct LocationDetailBottomSheet<FloatingImage: View, Content: View>: View {
    @Binding var contentScrollOffset: CGFloat
    @Binding var contentHeight: CGFloat

    let cornerRadius: CGFloat
    let scrollDisabled: Bool
    let floatingImage: FloatingImage
    let content: Content

    init(
        cornerRadius: CGFloat = 32,
        contentScrollOffset: Binding<CGFloat>,
        contentHeight: Binding<CGFloat>,
        scrollDisabled: Bool = false,
        @ViewBuilder floatingImage: () -> FloatingImage,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        _contentScrollOffset = contentScrollOffset
        _contentHeight = contentHeight
        self.scrollDisabled = scrollDisabled
        self.floatingImage = floatingImage()
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Track top offset to gate sheet drag while the content is scrolled.
                Color.clear
                    .frame(height: 0)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: LocationDetailScrollOffsetKey.self,
                                value: geometry.frame(
                                    in: .named("LocationDetailScroll")
                                ).minY
                            )
                        }
                    }

                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .background(Constants.Surface)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: LocationDetailContentHeightKey.self,
                        value: geometry.size.height
                    )
                }
            }
        }
        .scrollDisabled(scrollDisabled)
        .coordinateSpace(name: "LocationDetailScroll")
        .onPreferenceChange(LocationDetailScrollOffsetKey.self) { value in
            contentScrollOffset = value
        }
        .onPreferenceChange(LocationDetailContentHeightKey.self) { value in
            contentHeight = max(value, 1)
        }
        .background(Constants.Surface)
        .clipShape(
            .rect(
                topLeadingRadius: cornerRadius,
                topTrailingRadius: cornerRadius
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -1)
//        .overlay(alignment: .top) {
//            floatingImage
//                .offset(y: -36)
//                .zIndex(1)
//                .allowsHitTesting(false)
//        }
    }
}

#Preview("LocationDetailBottomSheet") {
    LocationDetailBottomSheet(
        cornerRadius: 32,
        contentScrollOffset: .constant(0),
        contentHeight: .constant(0),
        floatingImage: {
            LocationDetailHeroImage(imageName: "defaultTripPlaceholder")
        },
        content: {
            LocationDetailSummaryStrip(
                distanceText: "395km",
                visitorsText: "1,200+ visited",
                visitorsAvatarCount: 3
            )
            LocationDetailHeaderSection(
                title: "Hotpot",
                address: "251 Nguyen Van Troi, P12, Da Lat City",
                descriptionText: "This place combines casual dining with warm local service."
            )
            Spacer(minLength: 0)
        }
    )
    .frame(maxWidth: .infinity, maxHeight: 520, alignment: .top)
    .background(Constants.Background.ignoresSafeArea())
}
