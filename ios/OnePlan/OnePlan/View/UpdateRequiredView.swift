//
//  UpdateRequiredView.swift
//  OnePlan
//
//  Hard version gate. Presented as a full-screen cover at app launch when the
//  installed build is behind the App Store version (see VersionCheckManager).
//  There is no dismiss affordance — the only way out is to update.
//

import SwiftUI

struct UpdateRequiredView: View {
    let appInfo: VersionCheckManager.ReturnResult

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Image("updateRequiredCharacter")
                .resizable()
                .scaledToFit()
                .frame(height: 240)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Update Required")
                    .font(.beVietnamPro(24, weight: .bold))
                    .tracking(-0.72)
                    .foregroundStyle(Constants.ContentB)

                Text(
                    "A new version of OnePlan Travel is available. Please update to have a better experience."
                )
                .font(.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)

            PrimaryButton(title: "Update now") {
                guard let url = URL(string: appInfo.appURL) else { return }
                openURL(url)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Surface)
        .ignoresSafeArea()
    }
}

#Preview {
    UpdateRequiredView(
        appInfo: .init(
            currentVersion: "1.2.2",
            availableVersion: "1.3.0",
            releaseNotes: "",
            appLogo: "",
            appURL: "https://apps.apple.com/app/id000000000"
        )
    )
}
