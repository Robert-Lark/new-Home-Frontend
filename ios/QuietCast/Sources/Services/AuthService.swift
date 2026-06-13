import Foundation
import Observation
import Supabase

/// Email-OTP auth (auth-account.md §3.5): signInWithOTP → verifyOTP(type: .email). Same auth.users
/// rows and same JWTs as the web magic-link flow. The handle_new_user trigger creates the profiles
/// row server-side, so no client bootstrap insert is needed.
@MainActor
@Observable
final class AuthService {
    private(set) var user: User?
    var isSignedIn: Bool { user != nil }
    var userID: String? { user?.id.uuidString.lowercased() }
    var email: String? { user?.email }

    private var watchTask: Task<Void, Never>?

    init() {
        user = Supa.client.auth.currentUser
        watchTask = Task { [weak self] in
            for await state in Supa.client.auth.authStateChanges {
                await MainActor.run { self?.user = state.session?.user ?? Supa.client.auth.currentUser }
            }
        }
    }

    /// Restore any persisted session on launch (refreshes tokens if needed).
    func restore() async {
        user = try? await Supa.client.auth.session.user
    }

    /// Step 1: request the OTP. shouldCreateUser:true — login and signup are one flow.
    func sendCode(email: String) async throws {
        try await Supa.client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    /// Step 2: verify the 6-digit code; establishes the session for the same auth.users row.
    func verify(email: String, code: String) async throws {
        _ = try await Supa.client.auth.verifyOTP(email: email, token: code, type: .email)
        user = Supa.client.auth.currentUser
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
        user = nil
    }

    /// Current access token (JWT) for the iOS-facing delete endpoint's Authorization: Bearer header.
    func accessToken() async -> String? {
        try? await Supa.client.auth.session.accessToken
    }

    enum DeleteResult: Equatable { case ok, message(String) }

    /// In-app account deletion (App Store 5.1.1(v)). Calls the web app's POST /api/account/delete
    /// with Bearer JWT + {"confirm":"DELETE"}; the endpoint validates the token and runs the same
    /// admin deleteUser + cascade as the web settings flow (auth-account.md §6).
    func deleteAccount() async -> DeleteResult {
        guard let token = await accessToken() else { return .message("Sign in first.") }
        var req = URLRequest(url: Config.webAppBase.appendingPathComponent("api/account/delete"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["confirm": "DELETE"])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                await signOut()
                return .ok
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                return .message(err)
            }
            return .message("Could not delete your account — try again.")
        } catch {
            return .message("Could not reach the server — check your connection.")
        }
    }
}
