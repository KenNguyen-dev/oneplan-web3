//
//  LoginView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        ZStack(alignment: .top) {
            Color(Color(red: 0.93, green: 0.93, blue: 0.92))
                .ignoresSafeArea()

            VStack {
                Spacer()

                LoopingVideoPlayer(assetName: "loginVideo")
                    .frame(width: 393, height: 393)
                    .clipped()
                    .padding(.bottom,24)

                HStack(alignment: .center, spacing: 10) {
                    Image("appLogoDark")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 33, height: 33)
                        .clipped()

                    // Brand name — not localized.
                    Text(verbatim: "One Plan")
                        .font(Font.custom("Be Vietnam Pro", size: 20))
                        .foregroundColor(.black)
                }

                VStack(spacing: 16) {
                    Text(
                        "Plan the trip, track expenses,\nand settle up - all in one."
                    )
                    .font(
                        Font.beVietnamPro(24, weight: .bold)
                    )
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.ContentB)
                    .padding(.bottom, 24)
                    

                    LoginProviderButton(
                        title: String(localized: "Continue with Apple"),
                        backgroundColor: .black,
                        foregroundColor: .white,
                        action: {
                            Task { await authService.signInWithApple() }
                        }
                    ) {
                        if authService.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "apple.logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                    }
                    .disabled(authService.isLoading)

                    LoginProviderButton(
                        title: String(localized: "Continue with Google"),
                        backgroundColor: .white,
                        foregroundColor: Constants.ContentB,
                        action: {
                            Task { await authService.signInWithGoogle() }
                        }
                    ) {
                        if authService.isLoading {
                            ProgressView()
                                .frame(width: 24, height: 24)
                        } else {
                            Image("google")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 6,
                                        style: .continuous
                                    )
                                )
                        }
                    }
                    .disabled(authService.isLoading)

                    VStack(spacing: 4) {
                        Text("By continuing, you accept our")
                            .foregroundColor(Constants.ContentM)

                        HStack(spacing: 0) {
                            Link(
                                "Terms of Service",
                                destination: URL(string: "https://oneplan.space/termandconditions")!
                            )
                            Text(verbatim: " & ")
                                .foregroundColor(Constants.ContentM)
                            Link(
                                "Privacy Policy",
                                destination: URL(string: "https://oneplan.space/privacy-policy")!
                            )
                        }
                        .foregroundColor(Constants.BlueBase)
                    }
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .multilineTextAlignment(.center)
                }

            }
        }
        .alert(
            "Sign In Error",
            isPresented: .init(
                get: { authService.error != nil },
                set: { if !$0 { authService.error = nil } }
            )
        ) {
            Button("OK") { authService.error = nil }
        } message: {
            if let error = authService.error {
                Text(error)
            }
        }
    }
}

private struct LoginProviderButton<Icon: View>: View {
    let title: String
    let backgroundColor: Color
    let foregroundColor: Color
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                icon()

                Text(title)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .lineLimit(1)
            }
            .frame(height: 52, alignment: .center)
            .padding(.horizontal, 100)
        }
        .foregroundColor(foregroundColor)
        .background(backgroundColor)
        .clipShape(Capsule())
        .accessibilityLabel(Text(title))
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
