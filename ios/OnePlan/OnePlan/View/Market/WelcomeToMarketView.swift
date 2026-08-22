//
//  LoginView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import StoreKit
import SwiftUI

struct WelcomeToMarketView: View {
    var onClose: () -> Void = {}
    @State private var isShowingSubscription = false
    @State private var payAsYouGoProduct: Product?

    private var feeDescription: String {
        if let price = payAsYouGoProduct?.displayPrice {
            return "From now on, you no longer need to spend hours researching travel and dining itineraries. You can buy and use the plan that best suits you for a very small fee (\(price))."
        }
        return "From now on, you no longer need to spend hours researching travel and dining itineraries. You can buy and use the plan that best suits you for a very small fee."
    }

    var body: some View {
        NavigationStack {
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

                        Text("Welcome to Market")
                            .font(Font.custom("Be Vietnam Pro", size: 32))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .top)

                        Text(feeDescription)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.White)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .frame(width: 300, alignment: .top)

                    Spacer(minLength: 300)

                    Button {
                        isShowingSubscription = true
                    } label: {
                        // Title
                        Text("Unlock with Pro")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconButton(
                        systemName: "xmark",
                        foregroundColor: .white,
                        action: onClose
                    )
                }
                .sharedBackgroundHiddenCompat()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $isShowingSubscription) {
            SubscriptionView()
            .interactiveDismissDisabled()
        }
        .task {
            guard payAsYouGoProduct == nil else { return }
            let fetched = try? await Product.products(for: ["pro_weekly"])
            payAsYouGoProduct = fetched?.first
        }
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 755, height: 700)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }
    private var bottomBackground: some View {
        Image("welcomeMarketBackground")
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
    WelcomeToMarketView()
}
