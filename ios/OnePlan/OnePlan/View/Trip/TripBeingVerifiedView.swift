//
//  LoginView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct TripBeingVerifiedView: View {
    @State private var showMainView = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            topBlurBackground
                .ignoresSafeArea(.all, edges: .top)
                .zIndex(1)

            bottomBackground
                .ignoresSafeArea(.all, edges: .bottom)

            VStack {

                VStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Image("appLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 33, height: 33)
                            .clipped()

                        // Nav Link
                        Text("One Plan")
                            .font(Font.custom("Be Vietnam Pro", size: 20))
                            .foregroundColor(.white)
                    }

                    Text("Your plan is being verified")
                        .font(Font.custom("Be Vietnam Pro", size: 32))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .top)

                    Text(
                        "We will send you a notification via the email address you used to register your account when the Plan verification process is complete. Let's make it!"
                    )
                    .font(Font.custom("Be Vietnam Pro", size: 13.40506))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.White)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.top, 60)
                .padding(.bottom, 20)
                .frame(width: 300, alignment: .top)

                Spacer(minLength: 300)

                Button {
                    showMainView = true
                } label: {
                    // Title
                    Text("Back to market")
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: 320)
                .glassProminentButtonStyleCompat()

            }
            .zIndex(2)
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showMainView) {
            MainView(deepLinkTripId: .constant(nil), initialTab: .market)
                .interactiveDismissDisabled(true)
        }
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 685, height: 685)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }
    private var bottomBackground: some View {
        Image("planBeingVerifiedBackground")
            .resizable()
            .scaledToFit()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .offset(y: 60)
    }
}

#Preview {
    TripBeingVerifiedView()
}
