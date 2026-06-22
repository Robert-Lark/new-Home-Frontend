import SwiftUI

@main
struct QuietCastApp: App {
    @State private var theme = ThemeStore()
    @State private var auth = AuthService()
    @State private var library = LibraryStore()
    @State private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(theme)
                .environment(auth)
                .environment(library)
                .environment(player)
                .qcThemed(theme.theme)
                .task {
                    player.library = library
                    await auth.restore()
                    await syncForCurrentUser()
                }
                .onChange(of: auth.userID) { _, _ in
                    Task { await syncForCurrentUser() }
                }
        }
    }

    /// On sign-in: load favorites/listen state and adopt the server-saved theme (re-seeds local).
    /// On sign-out: clear the per-user caches.
    private func syncForCurrentUser() async {
        guard let id = auth.userID else {
            library.clear()
            return
        }
        await library.load(force: true)
        if let details = await ProfileService.profileDetails(id) {
            theme.adopt(serverTheme: details.theme)
        }
    }
}
