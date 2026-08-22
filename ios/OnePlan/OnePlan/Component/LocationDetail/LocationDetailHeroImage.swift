import SwiftUI

struct LocationDetailHeroImage: View {
    let imageName: String

    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 70, height: 70)
            .clipShape(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.black.opacity(0.15), lineWidth: 0.73)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 3)
    }
}

#Preview("LocationDetailHeroImage") {
    LocationDetailHeroImage(imageName: "defaultTripPlaceholder")
        .padding(24)
        .background(Constants.Surface)
}
