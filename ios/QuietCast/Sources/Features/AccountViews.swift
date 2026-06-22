import SwiftUI

/// Email-OTP sign in (auth-account.md §3.5): email → 6-digit code. Same auth.users as the web.
struct AuthView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth

    enum Phase { case email, code }
    @State private var phase: Phase = .email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Sign in")
                        DisplayTitle(text: "Quiet Cast", size: 34, tracking: 3)
                        Text("Listen, save favorites, and keep your place. One email, a six-digit code — no password.")
                            .font(QCFont.body(15)).foregroundStyle(p.ink2).lineSpacing(4)
                    }

                    if phase == .email { emailStep } else { codeStep }

                    if let error { Notice(text: error, isError: true) }
                    Spacer(minLength: 40)
                }
                .padding(20)
                .padding(.bottom, 140)
            }
        }
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Email", text: $email, keyboard: .emailAddress)
            Button { Task { await send() } } label: { Text(busy ? "Sending…" : "Send code") }
                .buttonStyle(SubmitPillStyle())
                .disabled(busy || !email.contains("@"))
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We sent a six-digit code to \(email).").font(QCFont.body(14)).foregroundStyle(p.ink2)
            field("6-digit code", text: $code, keyboard: .numberPad)
            Button { Task { await verify() } } label: { Text(busy ? "Verifying…" : "Verify & sign in") }
                .buttonStyle(SubmitPillStyle())
                .disabled(busy || code.count < 6)
            Button { phase = .email; code = ""; error = nil } label: { Text("Use a different email") }
                .buttonStyle(GhostPillStyle())
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(label, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(QCFont.body(16)).foregroundStyle(p.ink)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 6).fill(p.surface1))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.hairline, lineWidth: 1))
    }

    private func send() async {
        busy = true; defer { busy = false }
        do { try await auth.sendCode(email: email.trimmingCharacters(in: .whitespaces)); phase = .code; error = nil }
        catch { self.error = "Couldn't send the code — check the email and try again." }
    }

    private func verify() async {
        busy = true; defer { busy = false }
        do { try await auth.verify(email: email.trimmingCharacters(in: .whitespaces), code: code.trimmingCharacters(in: .whitespaces)) }
        catch { self.error = "That code didn't work — re-enter it or request a new one." }
    }
}

/// Settings (auth-account.md §5): display name / status / bio / profile song, privacy, theme,
/// sign out, and in-app account deletion (App Store 5.1.1(v)).
struct SettingsView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss
    let reload: () async -> Void

    @State private var displayName = ""
    @State private var statusLine = ""
    @State private var bio = ""
    @State private var isPublic = false
    @State private var songRef: String?
    @State private var episodes: [Episode] = []
    @State private var loaded = false
    @State private var profileMessage: String?
    @State private var savingProfile = false

    @State private var showDelete = false
    @State private var deleteConfirm = ""
    @State private var deleteMessage: String?

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileGroup
                    privacyGroup
                    themeGroup
                    songGroup
                    accountGroup
                }
                .padding(20)
                .padding(.bottom, 140)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
    }

    private var profileGroup: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Profile")
                labeled("Display name") { TextField("", text: $displayName).textFieldStyle(.plain) }
                labeled("Status line") { TextField("", text: $statusLine).textFieldStyle(.plain) }
                labeled("Bio") {
                    TextField("", text: $bio, axis: .vertical).lineLimit(2...5).textFieldStyle(.plain)
                }
                if let profileMessage { Notice(text: profileMessage) }
                Button { Task { await saveProfile() } } label: { Text(savingProfile ? "Saving…" : "Save profile") }
                    .buttonStyle(SubmitPillStyle()).disabled(savingProfile)
            }
        }
    }

    private var privacyGroup: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Privacy")
                Toggle(isOn: $isPublic) {
                    Text(isPublic ? "Public profile" : "Private profile")
                        .font(QCFont.body(15)).foregroundStyle(p.ink)
                }
                .tint(p.ember)
                .onChange(of: isPublic) { _, newValue in Task { _ = await ProfileService.savePrivacy(isPublic: newValue) } }
                Text("Public means anyone can see your profile, rotation, and wall.")
                    .font(QCFont.body(12)).foregroundStyle(p.ink3)
            }
        }
    }

    private var themeGroup: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Theme")
                Picker("Theme", selection: Binding(
                    get: { themeStore.theme },
                    set: { newValue in themeStore.set(newValue); Task { _ = await ProfileService.saveTheme(newValue) } }
                )) {
                    Text("Dark").tag(QCTheme.dark)
                    Text("Light").tag(QCTheme.light)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var songGroup: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Profile signal")
                Menu {
                    Button("None") { songRef = nil; Task { await saveProfile() } }
                    ForEach(episodes) { ep in
                        Button("\(ep.catLabel) · \(ep.title)") { songRef = ep.slug; Task { await saveProfile() } }
                    }
                } label: {
                    HStack {
                        Text(songLabel).font(QCFont.body(15)).foregroundStyle(p.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(p.ink3)
                    }
                }
            }
        }
    }

    private var accountGroup: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Account")
                if let email = auth.email { Text(email).font(QCFont.mono(11)).foregroundStyle(p.ink3) }
                Button { Task { await auth.signOut(); dismiss() } } label: { Text("Sign out") }
                    .buttonStyle(GhostPillStyle())
                Button { showDelete = true } label: { Text("Delete account") }
                    .buttonStyle(GhostPillStyle())
                    .tint(p.emberDeep)
                Text("Deleting removes your profile, favorites, listening history, rotation, and submissions — permanently.")
                    .font(QCFont.body(12)).foregroundStyle(p.ink3)
                if let deleteMessage { Notice(text: deleteMessage, isError: true) }
            }
        }
        .alert("Delete your account?", isPresented: $showDelete) {
            TextField("Type DELETE to confirm", text: $deleteConfirm)
            Button("Cancel", role: .cancel) { deleteConfirm = "" }
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This is permanent. Type DELETE (all caps) to confirm.")
        }
    }

    private var songLabel: String {
        guard let ref = songRef else { return "None" }
        if let ep = episodes.first(where: { $0.slug == ref }) { return "\(ep.catLabel) · \(ep.title)" }
        return "Selected"
    }

    @ViewBuilder private func labeled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(QCFont.mono(9)).tracking(1).foregroundStyle(p.ink3)
            content()
                .font(QCFont.body(16)).foregroundStyle(p.ink)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(p.surface1))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.hairline, lineWidth: 1))
        }
    }

    private func load() async {
        guard let id = auth.userID else { return }
        async let rowA = ProfileService.profileRow(id)
        async let detailsA = ProfileService.profileDetails(id)
        async let epsA = (try? await SanityService.shared.episodes()) ?? []
        let row = await rowA
        let details = await detailsA
        episodes = await epsA
        displayName = row?.displayName ?? auth.email?.split(separator: "@").first.map(String.init) ?? ""
        statusLine = details?.statusLine ?? ""
        bio = details?.bio ?? ""
        isPublic = details?.isPublic ?? false
        songRef = details?.profileSongRef
        loaded = true
    }

    private func saveProfile() async {
        savingProfile = true; defer { savingProfile = false }
        switch await ProfileService.saveProfile(displayName: displayName, statusLine: statusLine, bio: bio, songRef: songRef) {
        case .success: profileMessage = "Saved."; await reload()
        case .failure(let e): profileMessage = e.message
        }
    }

    private func deleteAccount() async {
        guard deleteConfirm == "DELETE" else { deleteMessage = "Type DELETE (all caps) to confirm."; return }
        switch await auth.deleteAccount() {
        case .ok: dismiss()
        case .message(let m): deleteMessage = m
        }
    }
}
