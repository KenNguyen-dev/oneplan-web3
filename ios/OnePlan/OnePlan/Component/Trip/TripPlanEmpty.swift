import SwiftUI

struct TripPlanEmpty: View {
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No plans")
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .top)

                Text("Add your first plan to get started")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.ContentM)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(0)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 4)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(Constants.Surface)
        .cornerRadius(24)
    }
}

#Preview {
    TripPlanEmpty()
        .padding()
        .background(Constants.Background)
}
