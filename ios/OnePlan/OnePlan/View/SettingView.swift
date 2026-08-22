//
//  SettingView.swift
//  OnePlan
//
//  Created by ken on 5/4/26.
//

import SwiftUI
import StoreKit

struct SettingView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(UserProfileService.self) private var userProfileService
    @Environment(AuthService.self) private var authService
    @Environment(StoreManager.self) private var storeManager
    @State private var isShowingEditDisplayName = false
    @State private var editedDisplayName = ""
    @State private var originalDisplayName = ""
    @State private var isShowingSubscription = false
    @State private var isSavingDisplayName = false
    @State private var isSigningOut = false
    @State private var didCommitDisplayNameChange = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var isShowingCurrencyPicker = false
    @State private var isShowingWallet = false
    @State private var walletAddress = ""

    /// Shown beside the row so the wallet is recognisable without opening it.
    private var walletAddressDisplay: String {
        guard walletAddress.count > 8 else { return "" }
        return "\(walletAddress.prefix(4))...\(walletAddress.suffix(4))"
    }
    @State private var selectedCurrency: Currency = .USD
    @State private var hasLoadedInitialCurrency = false
    @State private var isShowingLanguagePicker = false
    @State private var selectedLanguage: AppLanguage = .current
    @State private var showLanguageRestartAlert = false
    @State private var serverCommitHash: String?
    @State private var engagementPushEnabled = false
    @State private var hasLoadedEngagementSetting = false

    private let privacyPolicyURL = URL(string: "https://oneplan.space/privacy-policy")
    private let termsAndConditionsURL = URL(string: "https://oneplan.space/termandconditions")
    private let supportURL = URL(string: "https://t.me/+C6MDB5xslyRlZTZl")

    private var currencyDisplayValue: String {
        "\(selectedCurrency.rawValue) (\(selectedCurrency.symbol))"
    }

    private var sections: [SettingSection] {
        [
            SettingSection(
                header: .init(
                    systemIconName: "person.crop.circle.fill",
                    title: "Personal"
                ),
                items: [
                    .init(
                        iconAssetName: "settingDisplayName",
                        title: "Display name",
                        trailingValue: userProfileService.profile?.displayName ?? "One Plan User",
                        action: .editDisplayName
                    ),
                    .init(
                        iconAssetName: "walletIcon",
                        title: "My wallet",
                        trailingValue: walletAddressDisplay,
                        showsDisclosure: true,
                        action: .myWallet
                    ),
                    .init(
                        iconAssetName: "settingCurrency",
                        title: "Currency",
                        trailingValue: currencyDisplayValue,
                        showsDisclosure: true,
                        action: .currency
                    ),
                    .init(
                        iconAssetName: "",
                        systemIconName: "globe",
                        title: "Language",
                        trailingValue: selectedLanguage.displayName,
                        showsDisclosure: true,
                        action: .language
                    ),
                    .init(
                        iconAssetName: "",
                        systemIconName: "bell.badge.fill",
                        title: "Trip tips & nudges",
                        toggle: $engagementPushEnabled
                    )
                ]
            ),
            SettingSection(
                header: .init(
                    systemIconName: "creditcard.fill",
                    title: "One Plan"
                ),
                items: [
                    .init(
                        iconAssetName: "settingPrivacyPolicy",
                        title: "Privacy Policy",
                        showsDisclosure: true,
                        action: .privacyPolicy
                    ),
                    .init(
                        iconAssetName: "settingTerms",
                        title: "Terms and Conditions",
                        showsDisclosure: true,
                        action: .termsAndConditions
                    ),
                ]
            ),
            SettingSection(
                header: .init(
                    systemIconName: "wineglass.fill",
                    title: "About us"
                ),
                items: [
                    .init(
                        iconAssetName: "settingFeedback",
                        title: "Rate your experiences",
                        showsDisclosure: true,
                        action: .rateExperience
                    ),
                    .init(
                        iconAssetName: "settingSupport",
                        title: "Contact support",
                        showsDisclosure: true,
                        action: .contactSupport
                    ),
                ]
            ),
            SettingSection(
                header: .init(
                    systemIconName: "exclamationmark.shield.fill",
                    title: "Danger zone"
                ),
                items: [
                    .init(
                        iconAssetName: "settingLogout",
                        title: "Log out",
                        action: .logout
                    ),
                    .init(
                        iconAssetName: "settingDeleteAccount",
                        title: "Delete my account",
                        titleColor: Color(red: 1, green: 45 / 255, blue: 85 / 255),
                        action: .deleteAccount
                    ),
                ]
            ),
        ]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                premiumCard

                ForEach(sections) { section in
                    settingSection(section)
                }

                buildFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Constants.Background.ignoresSafeArea())
        .task {
            await userProfileService.fetchProfile()
            if let apiCurrency = userProfileService.profile?.preferredCurrency.value1,
               let currency = Currency(from: apiCurrency) {
                selectedCurrency = currency
            }
            hasLoadedInitialCurrency = true
            engagementPushEnabled = userProfileService.profile?.engagementPushEnabled ?? false
            hasLoadedEngagementSetting = true
        }
        .task {
            await fetchServerCommitHash()
        }
        .onChange(of: selectedCurrency) { _, newCurrency in
            guard hasLoadedInitialCurrency else { return }
            Task {
                guard let apiCurrency = newCurrency.toAPICurrency else {
                    userProfileService.error = "Unsupported currency"
                    return
                }
                await userProfileService.updatePreferredCurrency(apiCurrency)
            }
        }
        .sheet(isPresented: $isShowingEditDisplayName) {
            EditDisplayNameSheet(
                displayName: $editedDisplayName,
                isSaving: isSavingDisplayName,
                onDismiss: {
                    isShowingEditDisplayName = false
                },
                onSubmit: {
                    Task {
                        await commitDisplayNameEditAndDismiss()
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(36)
            .presentationBackground(Constants.Neutral50)
            .interactiveDismissDisabled(isSavingDisplayName)
        }
        .fullScreenCover(isPresented: $isShowingSubscription) {
            SubscriptionView()
                .interactiveDismissDisabled(false)
        }
        .navigationDestination(isPresented: $isShowingWallet) {
            OnePlanWalletView()
        }
        .task {
            walletAddress =
                (try? await WalletWithdrawService.shared.myWallet().publicKey) ?? ""
        }
        .sheet(isPresented: $isShowingCurrencyPicker) {
            CurrencyPickerBottomSheet(
                selectedCurrency: Binding(
                    get: { selectedCurrency },
                    set: { newValue in
                        if let newValue { selectedCurrency = newValue }
                    }
                )
            )
        }
        .sheet(isPresented: $isShowingLanguagePicker) {
            LanguagePickerBottomSheet(selectedLanguage: $selectedLanguage)
        }
        .onChange(of: engagementPushEnabled) { _, newValue in
            // Flipping ON is the explicit marketing-consent action (App Store
            // 4.5.4): pass grantConsent so the server stamps the audit record.
            guard hasLoadedEngagementSetting else { return }
            Task {
                await userProfileService.setEngagementPushEnabled(
                    newValue,
                    grantConsent: newValue
                )
            }
        }
        .onChange(of: selectedLanguage) { _, newLanguage in
            // iOS only switches the bundle language on launch, so persist the
            // override and ask the user to relaunch.
            guard newLanguage != AppLanguage.current else { return }
            newLanguage.apply()
            showLanguageRestartAlert = true
            // Sync to the server so server-localized push notifications match
            // the chosen language (token registration alone won't re-send it).
            Task {
                await userProfileService.updateLocale(newLanguage.engagementLocale)
            }
        }
        .onChange(of: isShowingEditDisplayName) { oldValue, newValue in
            guard oldValue, !newValue else { return }

            Task {
                await commitDisplayNameEditIfNeeded()
            }
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    _ = await authService.deleteAccount()
                    isDeletingAccount = false
                }
            }
        } message: {
            Text("This action is permanent. All your trips, expenses, photos, and data will be deleted forever.")
        }
        .alert("Restart Required", isPresented: $showLanguageRestartAlert) {
            Button("OK", role: .cancel) {
                quitForLanguageChange()
            }
        } message: {
            Text("Please reopen One Plan to finish switching the app language.")
        }
    }

    private var premiumCard: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    OnePlanProLogoBadge(size: 32, showsShadow: true)

                    Text("One Plan")
                        .font(
                            Font.beVietnamPro(25, weight: .semibold)
                        )
                        .foregroundStyle(Constants.White)
                        .tracking(-1.2)

                    Text("Pro")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.BlueBase)
                        .tracking(-0.52)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Constants.Surface)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 6,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 6,
                                style: .continuous
                            )
                            .stroke(Constants.BlueBase, lineWidth: 1)
                        }
                }

                Text(
                    "Planning your trips with friends in a funniest & easiest ways !!!"
                )
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.White.opacity(0.76))
                .tracking(-0.65)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            upgradeButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 110)
        .background {
            LinearGradient(
                stops: [
                    Gradient.Stop(
                        color: Color(red: 0.2, green: 0.36, blue: 1),
                        location: 0.00
                    ),
                    Gradient.Stop(
                        color: Color(red: 0.12, green: 0.22, blue: 0.6),
                        location: 1.00
                    ),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var upgradeButton: some View {
        Button {
            isShowingSubscription = true
        } label: {
            Text(storeManager.isPro ? String(localized: "View Plan") : String(localized: "Upgrade now"))
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .foregroundStyle(Constants.White)
                .tracking(-0.7)
                .frame(width: 119, height: 41)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 31, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 71 / 255, green: 108 / 255, blue: 1)
                                .opacity(0.19),
                            Color(red: 0, green: 80 / 255, blue: 217 / 255),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 31, style: .continuous)
                .stroke(Constants.White, lineWidth: 1.5)
        }
        .shadow(
            color: Color(red: 100 / 255, green: 146 / 255, blue: 1).opacity(
                0.39
            ),
            radius: 3,
            y: 3
        )
        .shadow(
            color: Color(red: 149 / 255, green: 209 / 255, blue: 1).opacity(
                0.25
            ),
            radius: 11.4,
            y: 13
        )
    }

    private var buildFooter: some View {
        VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Constants.Black,
                                Constants.BlueBase,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Image("appLogoCutout")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
            .frame(width: 26, height: 26)

            VStack(spacing: 3) {
                Text(versionDisplayText)
                Text(serverCommitDisplayText)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Constants.ContentM)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }

    private var versionDisplayText: String {
        "Version \(bundleValue(for: "CFBundleShortVersionString")) (\(bundleValue(for: "CFBundleVersion")))"
    }

    private var serverCommitDisplayText: String {
        guard let serverCommitHash,
              !serverCommitHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "--"
        }

        return "\(String(serverCommitHash.prefix(7)))"
    }

    private func bundleValue(for key: String) -> String {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "--"
        }

        return value
    }

    private func settingSection(_ section: SettingSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: section.header.systemIconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.ContentM)
                    .frame(width: 16, height: 16)

                Text(section.header.title)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.28)
            }
            .padding(.bottom, 10)

            Rectangle()
                .fill(Constants.Neutral200)
                .frame(height: 1)
                .opacity(0.6)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.offset) {
                    index,
                    item in
                    settingRow(item)

                    if index < section.items.count - 1 {
                        Rectangle()
                            .fill(Constants.Neutral200)
                            .frame(height: 1)
                            .opacity(0.6)
                    }
                }
            }
            .padding(.top, 5)
        }
        .padding(12)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func settingRow(_ item: SettingItem) -> some View {
        Group {
            if item.toggle != nil {
                // Toggle rows aren't tappable buttons — the control handles input.
                settingRowContent(item)
            } else if let action = item.action {
                Button {
                    handle(itemAction: action)
                } label: {
                    settingRowContent(item)
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled || isSigningOut)
            } else {
                settingRowContent(item)
            }
        }
        .opacity(item.isEnabled ? 1 : 0.65)
    }

    private func settingRowContent(_ item: SettingItem) -> some View {
        HStack(spacing: 6) {
            if isSigningOut && item.action == .logout {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else if let systemIconName = item.systemIconName {
                Image(systemName: systemIconName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Constants.ContentB)
                    .frame(width: 24, height: 24)
            } else {
                settingIcon(item.iconAssetName, size: 24)
            }

            Text(item.title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(item.titleColor)
                .tracking(-0.28)

            Spacer(minLength: 0)

            if let toggle = item.toggle {
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .tint(Constants.BlueBase)
            } else {
                if let trailingValue = item.trailingValue {
                    Text(trailingValue)
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.8)
                }

                if item.showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Constants.ContentM.opacity(0.85))
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
    }

    private func settingIcon(_ assetName: String, size: CGFloat) -> some View {
        Image(assetName)
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private func handle(itemAction: SettingItemAction) {
        switch itemAction {
        case .editDisplayName:
            originalDisplayName = userProfileService.profile?.displayName ?? ""
            editedDisplayName = originalDisplayName
            didCommitDisplayNameChange = false
            isShowingEditDisplayName = true
        case .myWallet:
            isShowingWallet = true
        case .currency:
            isShowingCurrencyPicker = true
        case .language:
            isShowingLanguagePicker = true
        case .logout:
            Task {
                isSigningOut = true
                await authService.signOutRemotely()
                isSigningOut = false
            }
        case .privacyPolicy:
            guard let privacyPolicyURL else { return }
            openURL(privacyPolicyURL)
        case .termsAndConditions:
            guard let termsAndConditionsURL else { return }
            openURL(termsAndConditionsURL)
        case .rateExperience:
            requestReview()
        case .contactSupport:
            guard let supportURL else { return }
            openURL(supportURL)
        case .deleteAccount:
            showDeleteAccountConfirmation = true
        }
    }

    private func commitDisplayNameEditAndDismiss() async {
        await commitDisplayNameEditIfNeeded()
        isShowingEditDisplayName = false
    }

    private func commitDisplayNameEditIfNeeded() async {
        guard !didCommitDisplayNameChange else { return }

        let normalizedDisplayName = editedDisplayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedOriginalDisplayName = originalDisplayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard normalizedDisplayName != normalizedOriginalDisplayName else { return }
        guard !normalizedDisplayName.isEmpty else { return }

        didCommitDisplayNameChange = true

        isSavingDisplayName = true
        defer { isSavingDisplayName = false }

        await userProfileService.updateDisplayName(normalizedDisplayName)
        if userProfileService.error != nil {
            didCommitDisplayNameChange = false
            return
        }
        originalDisplayName = normalizedDisplayName
    }

    /// iOS only picks up the language override on launch, so terminate the app
    /// after the user acknowledges the restart prompt. Suspend first so the app
    /// animates to the background before exiting, instead of vanishing abruptly.
    private func quitForLanguageChange() {
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            exit(0)
        }
    }

    private func fetchServerCommitHash() async {
        let url = APIEnvironment.current.serverURL
            .appendingPathComponent("health")
            .appendingPathComponent("live")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return
            }

            let liveResponse = try JSONDecoder().decode(
                ServerLiveResponse.self,
                from: data
            )
            serverCommitHash = liveResponse.commitHash
        } catch {
            serverCommitHash = nil
        }
    }
}

private struct ServerLiveResponse: Decodable {
    let commitHash: String?
}

private struct SettingSection: Identifiable {
    let id = UUID()
    let header: SettingSectionHeader
    let items: [SettingItem]
}

private struct SettingSectionHeader {
    let systemIconName: String
    let title: LocalizedStringKey
}

private struct SettingItem {
    let iconAssetName: String
    /// When set, an SF Symbol is rendered instead of `iconAssetName` (used for
    /// rows that have no custom icon asset, e.g. Language).
    var systemIconName: String? = nil
    let title: LocalizedStringKey
    var trailingValue: String? = nil
    var showsDisclosure: Bool = false
    var titleColor: Color = Constants.ContentB
    var action: SettingItemAction? = nil
    var isEnabled: Bool = true
    /// When set, the row renders a trailing toggle instead of a tappable
    /// value/chevron (e.g. "Trip tips & nudges").
    var toggle: Binding<Bool>? = nil
}

private enum SettingItemAction {
    case editDisplayName
    case myWallet
    case currency
    case language
    case logout
    case privacyPolicy
    case termsAndConditions
    case rateExperience
    case contactSupport
    case deleteAccount
}

private struct EditDisplayNameSheet: View {
    @Binding var displayName: String
    let isSaving: Bool
    let onDismiss: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.44, style: .continuous)
                    .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                    .frame(width: 35.2, height: 4.89)
                    .padding(.top, 12.5)

                Spacer(minLength: 0)

                VStack(spacing: 28) {
                    Text("What’s your name?")
                        .font(Font.custom("Be Vietnam Pro", size: 15))
                        .foregroundStyle(Constants.Neutral700)
                        .tracking(-0.75)

                    TextField("", text: $displayName)
                        .font(Font.custom("Be Vietnam Pro", size: 48))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-2.4)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(onSubmit)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 122)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Constants.Neutral50)

            SettingSheetDismissButton(action: onDismiss)
                .disabled(isSaving)
                .opacity(isSaving ? 0.6 : 1)
                .padding(.bottom, 51)
        }
    }
}

private struct SettingSheetDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: Color(
                                        red: 0.925,
                                        green: 0.925,
                                        blue: 0.925
                                    ),
                                    location: 0
                                ),
                                .init(
                                    color: Color(
                                        red: 0.7,
                                        green: 0.7,
                                        blue: 0.7
                                    ),
                                    location: 0.745
                                ),
                                .init(
                                    color: Color(
                                        red: 0.922,
                                        green: 0.922,
                                        blue: 0.922
                                    ),
                                    location: 1
                                ),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .fill(Constants.White.opacity(0.85))
                    .frame(width: 43.658, height: 16.346)
                    .blur(radius: 2.3)
                    .offset(y: -18)
                    .blendMode(.plusLighter)

                Image(systemName: "xmark")
                    .font(.system(size: 17.8, weight: .light))
                    .foregroundStyle(Constants.ContentB.opacity(0.85))
            }
            .frame(width: 52, height: 52)
            .overlay {
                Circle()
                    .stroke(Constants.White, lineWidth: 1.5)
            }
            .shadow(
                color: Color(red: 0.588, green: 0.588, blue: 0.588).opacity(
                    0.25
                ),
                radius: 5.7,
                x: 0,
                y: 13
            )
            .shadow(
                color: Color(red: 0.765, green: 0.765, blue: 0.765).opacity(
                    0.39
                ),
                radius: 3.05,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingView()
        .environment(UserProfileService())
        .environment(AuthService())
}
