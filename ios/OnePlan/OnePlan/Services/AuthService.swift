//
//  AuthService.swift
//  OnePlan
//

import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import LocalAuthentication
import Security

@MainActor
@Observable
final class AuthService {
    var isAuthenticated = false
    var isLoading = false
    var error: String?

    private let googleClientID = "559176877871-535pl0kskgdabrdg41h6nr03ira3vvmk.apps.googleusercontent.com"
    private var sessionObserver: Any?
    private var appleRevocationObserver: Any?

    init() {
        isAuthenticated = AuthTokenStore.shared.accessToken != nil
        if isAuthenticated {
            Self.bootstrapWalletInBackground()
        }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .authSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isAuthenticated else { return }
                self.signOut()
            }
        }
        appleRevocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isAuthenticated else { return }
                self.signOut()
            }
        }
    }

    func configureGoogleSignIn() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
    }

    func handleURL(_ url: URL) -> Bool {
        // OAuth callbacks are consumed by ASWebAuthenticationSession
        // internally on iOS 13+ (we target iOS 26+; GoogleSignIn 9.1.0,
        // AppAuth 2.0.0). iOS sometimes also delivers the redirect here
        // via .onOpenURL — forwarding it to GIDSignIn.handle(_:) walks
        // into AppAuth's OIDAuthorizationSession, which raises an
        // uncatchable Obj-C NSException when the flow's callback has
        // already been invoked (delete account → re-signin reliably
        // triggers this). Recognize the OAuth callback by scheme so we
        // swallow it instead of forwarding, and so it doesn't fall
        // through to the trip/friend deep-link parsers.
        guard let scheme = url.scheme?.lowercased(),
              scheme == reverseGoogleClientIDScheme else {
            return false
        }
        return true
    }

    private var reverseGoogleClientIDScheme: String {
        let suffix = ".apps.googleusercontent.com"
        let base = googleClientID.hasSuffix(suffix)
            ? String(googleClientID.dropLast(suffix.count))
            : googleClientID
        return "com.googleusercontent.apps.\(base)".lowercased()
    }

    func signInWithGoogle() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            error = String(localized: "Unable to find root view controller")
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                error = String(localized: "Failed to get ID token from Google")
                return
            }

            let displayName = result.user.profile?.givenName
            let email = result.user.profile?.email

            let response = try await APIClient.shared.socialLogin(.init(
                body: .json(.init(
                    identityToken: idToken,
                    provider: .GOOGLE,
                    displayName: displayName,
                    email: email
                ))
            ))

            let authResponse = try response.ok.body.json
            AuthTokenStore.shared.accessToken = authResponse.accessToken
            AuthTokenStore.shared.refreshToken = authResponse.refreshToken
            isAuthenticated = true
            AnalyticsClient.shared.userDidAuthenticate()
            Self.bootstrapWalletInBackground()
        } catch is GIDSignInError {
            // User cancelled — don't show error
        } catch {
            self.error = String(localized: "Sign in failed. Please try again.")
        }
    }

    func signInWithApple() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Generate a cryptographically random nonce. Apple hashes the value
            // we set on the request and echoes the hash back in the JWT's
            // `nonce` claim; we forward the raw value to our server, which
            // recomputes the hash and rejects mismatches. Protects against
            // replay of a captured Apple identity token.
            let rawNonce = Self.makeRandomNonce()
            let hashedNonce = Self.sha256Hex(rawNonce)

            let delegate = AppleSignInDelegate()
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate

            let credential = try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                controller.performRequests()
            }

            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                error = String(localized: "Failed to get identity token from Apple")
                return
            }

            // Save Apple user ID for credential state checks
            AuthTokenStore.shared.appleUserID = credential.user

            // fullName and email are only provided on first authorization
            var displayName: String?
            if let fullName = credential.fullName {
                displayName = PersonNameComponentsFormatter().string(from: fullName)
                if displayName?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                    displayName = nil
                }
            }
            let email = credential.email

            let response = try await APIClient.shared.socialLogin(.init(
                body: .json(.init(
                    identityToken: idToken,
                    provider: .APPLE,
                    displayName: displayName,
                    email: email,
                    nonce: rawNonce
                ))
            ))

            let authResponse = try response.ok.body.json
            AuthTokenStore.shared.accessToken = authResponse.accessToken
            AuthTokenStore.shared.refreshToken = authResponse.refreshToken
            isAuthenticated = true
            AnalyticsClient.shared.userDidAuthenticate()
            Self.bootstrapWalletInBackground()
        } catch let authError as ASAuthorizationError where authError.code == .canceled {
            // User cancelled — don't show error
        } catch is ASAuthorizationError {
            self.error = String(localized: "Apple Sign In failed. Please try again.")
        } catch {
            self.error = String(localized: "Sign in failed. Please try again.")
        }
    }

    func checkAppleCredentialState() async {
        guard isAuthenticated,
              let appleUserID = AuthTokenStore.shared.appleUserID else { return }

        do {
            let state = try await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: appleUserID)
            switch state {
            case .revoked:
                signOut()
            case .authorized, .notFound, .transferred:
                break
            @unknown default:
                break
            }
        } catch {
            // Network error — allow offline access
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        AuthTokenStore.shared.clear()
        isAuthenticated = false
        Task { await WalletService.shared.reset() }
    }

    func signOutRemotely() async {
        let refreshToken = AuthTokenStore.shared.refreshToken

        if let refreshToken, !refreshToken.isEmpty {
            do {
                let _ = try await APIClient.shared.logout(
                    .init(
                        body: .json(
                            .init(refreshToken: refreshToken)
                        )
                    )
                )
            } catch {
                // Sign out locally even if remote revoke fails.
                self.error = String(localized: "Logged out locally. Server logout failed.")
            }
        }

        signOut()
    }

    // MARK: - Nonce helpers (Apple Sign-In replay protection)

    private static func makeRandomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        // URL-safe alphabet keeps the nonce well-formed when serialized as JSON.
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func deleteAccount() async -> Bool {
        // 1. Authenticate with biometrics or passcode
        let context = LAContext()
        var authError: NSError?

        let canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &authError
        )
        let canUsePasscode = context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &authError
        )

        guard canUseBiometrics || canUsePasscode else {
            self.error = String(localized: "Authentication not available on this device")
            return false
        }

        let policy: LAPolicy = canUseBiometrics
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            let authenticated = try await context.evaluatePolicy(
                policy,
                localizedReason: "Confirm to permanently delete your account"
            )
            guard authenticated else {
                self.error = String(localized: "Authentication failed")
                return false
            }
        } catch {
            // User cancelled or authentication failed
            self.error = nil
            return false
        }

        // 2. Call API to delete account
        isLoading = true
        defer { isLoading = false }

        do {
            let _ = try await APIClient.shared.deleteAccount()
            StoreManager.clearEntitlementCache()
            signOut()
            return true
        } catch {
            self.error = String(localized: "Failed to delete account. Please try again.")
            return false
        }
    }

    /// Privy create + server link after auth. Does not block sign-in.
    private static func bootstrapWalletInBackground() {
        Task {
            guard WalletService.shared.isConfigured else { return }
            do {
                _ = try await WalletService.shared.ensureLinked()
            } catch {
                print("Wallet bootstrap: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Apple Sign-In delegate bridge

private final class AppleSignInDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
            as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: ASAuthorizationError(.failed))
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
