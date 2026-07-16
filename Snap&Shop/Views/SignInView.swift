import SwiftUI
import AuthenticationServices

/// Gate screen shown after onboarding when the user is not signed in.
/// Uses Sign in with Apple; the resulting identity token is stored in the Keychain
/// and sent as a Bearer token on every backend request.
struct SignInView: View {

    @EnvironmentObject private var authState: AuthState
    @Environment(\.colorScheme) private var colorScheme

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                iconCard
                    .padding(.bottom, Spacing.xl)

                VStack(spacing: Spacing.sm) {
                    Text("Sign In to Continue")
                        .font(Typography.title)
                        .foregroundStyle(Color.Brand.textPrimary)

                    Text("Your scan history and saved items stay on your device. Sign in lets us verify your identity — nothing more.")
                        .font(Typography.body)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                }

                Spacer()

                VStack(spacing: Spacing.md) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleResult(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .padding(.horizontal, Spacing.xl)
                    .accessibilityIdentifier("signInWithAppleButton")

                    #if DEBUG
                    Button {
                        authState.signInAsDemo()
                    } label: {
                        Text("Continue in demo mode")
                            .font(Typography.body)
                            .foregroundStyle(Color.Brand.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(Color.Brand.textSecondary.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, Spacing.xl)
                    .accessibilityIdentifier("demoModeButton")
                    #endif

                    if let error = errorMessage {
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(Color.Brand.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                            .transition(.opacity)
                    }

                    Text("Protected by Sign in with Apple. Your data is never sold.")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxl)
                }
                .padding(.bottom, Spacing.xxxl)
            }
        }
    }

    // MARK: — Icon

    private var iconCard: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.Brand.accent.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)

            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.Brand.surface)
                .frame(width: 160, height: 160)
                .shadow(color: Color.Brand.accent.opacity(0.14), radius: 28, y: 10)

            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.Brand.accent)
        }
    }

    // MARK: — Result handler

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        withAnimation { errorMessage = nil }

        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData   = credential.identityToken,
                let token       = String(data: tokenData, encoding: .utf8)
            else {
                withAnimation { errorMessage = "Sign in failed — could not read token." }
                return
            }

            let name: String? = {
                guard let components = credential.fullName else { return nil }
                return PersonNameComponentsFormatter().string(from: components)
                    .nilIfEmpty()
            }()

            authState.signIn(
                userId:        credential.user,
                identityToken: token,
                displayName:   name
            )

        case .failure(let error):
            let appleError = error as? ASAuthorizationError
            // Don't show an error when the user simply cancels.
            if appleError?.code != .canceled {
                withAnimation { errorMessage = "Sign in failed — please try again." }
                print("[Auth] Sign in with Apple error: \(error)")
            }
        }
    }
}

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
}
