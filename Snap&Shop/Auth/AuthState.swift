import Combine
import Foundation
import AuthenticationServices

/// App-wide authentication state. Loaded from Keychain on init; never touches UserDefaults.
///
/// Token lifetime note: Apple identity tokens expire in ~10 minutes. For Phase 2 this is
/// acceptable — the acceptance test signs in then immediately scans. A production hardening
/// step (Phase 3+) should add a /auth/exchange endpoint to the backend that returns a
/// long-lived session JWT, replacing the short-lived identity token stored here.
final class AuthState: ObservableObject {

    @Published private(set) var userId: String?
    @Published private(set) var identityToken: String?
    @Published private(set) var displayName: String?

    var isSignedIn: Bool { userId != nil && identityToken != nil }

    // MARK: — Keychain keys

    private enum Keys {
        static let userId        = "auth.userId"
        static let identityToken = "auth.identityToken"
        static let displayName   = "auth.displayName"
    }

    // MARK: — Init

    init() {
        userId        = KeychainStore.load(key: Keys.userId)
        identityToken = KeychainStore.load(key: Keys.identityToken)
        displayName   = KeychainStore.load(key: Keys.displayName)
    }

    // MARK: — Mutations (always call on MainActor)

    func signIn(userId: String, identityToken: String, displayName: String?) {
        self.userId        = userId
        self.identityToken = identityToken
        self.displayName   = displayName

        KeychainStore.save(userId,        key: Keys.userId)
        KeychainStore.save(identityToken, key: Keys.identityToken)
        if let name = displayName {
            KeychainStore.save(name, key: Keys.displayName)
        }
    }

    func signOut() {
        userId        = nil
        identityToken = nil
        displayName   = nil

        KeychainStore.delete(key: Keys.userId)
        KeychainStore.delete(key: Keys.identityToken)
        KeychainStore.delete(key: Keys.displayName)
    }

    // MARK: — Revocation check

    /// Called on every cold launch. Signs out if Apple has revoked the credential
    /// (user removed the app from their Apple ID settings).
    func checkRevocation() async {
        guard let userId else { return }
        let state = await withCheckedContinuation { (cont: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                cont.resume(returning: state)
            }
        }
        if state != .authorized {
            await MainActor.run { signOut() }
        }
    }
}
