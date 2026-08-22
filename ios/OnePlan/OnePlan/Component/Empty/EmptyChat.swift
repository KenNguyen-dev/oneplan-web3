import SwiftUI

struct EmptyChat: View {
    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Image("emptyChat")
                .resizable()
                .scaledToFit()
                .frame(width: 165.449, height: 165.449)

            Text("No chat.")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .tracking(-0.64)
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentM)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#Preview {
    EmptyChat()
        .background(Constants.Background)
}
