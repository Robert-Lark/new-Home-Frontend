import SwiftUI

/// Read-only rotation grid (iOS v1: no add/reorder/unpin). Listener pins render from the snapshot
/// row — never re-resolved from profiles (profile.md §6.4).
struct RotationSection: View {
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL
    let title: String
    let connections: [Connection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(title)
                Spacer()
                if !connections.isEmpty { Text("\(connections.count)").font(QCFont.mono(9)).foregroundStyle(p.ink3) }
            }
            if connections.isEmpty {
                Text("Nothing pinned yet.").font(QCFont.body(14)).foregroundStyle(p.ink3)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                    ForEach(connections) { c in tile(c) }
                }
            }
        }
    }

    @ViewBuilder private func tile(_ c: Connection) -> some View {
        let inner = VStack(alignment: .leading, spacing: 6) {
            cover(c)
            Text(c.name).font(QCFont.bodyMedium(13)).foregroundStyle(p.ink).lineLimit(1)
            Chip(text: c.kind)
        }
        if let link = c.linkURL, !link.isEmpty {
            if link.hasPrefix("/"), let route = Route.from(href: link) {
                NavigationLink(value: route) { inner }.buttonStyle(.plain)
            } else if let u = URL(string: link) {
                Button { openURL(u) } label: { inner }.buttonStyle(.plain)
            } else { inner }
        } else { inner }
    }

    @ViewBuilder private func cover(_ c: Connection) -> some View {
        if let url = c.imageURL, let u = URL(string: url) {
            AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { p.recess }
                .aspectRatio(1, contentMode: .fill).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(p.recess).aspectRatio(1, contentMode: .fit)
                .overlay(Text(String(c.name.prefix(1)).uppercased()).font(QCFont.display(34)).foregroundStyle(p.ink2))
        }
    }
}

/// Comment wall: read + post + delete (owner/author) + report. Live-immediately, no review queue.
struct WallSection: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    let profileID: String
    let entries: [WallEntry]
    let wallOpen: Bool
    let isOwn: Bool
    let reload: () async -> Void

    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Wall")

            if wallOpen, auth.isSignedIn {
                composer
            } else if wallOpen, !auth.isSignedIn {
                Text("Sign in to leave a note.").font(QCFont.body(14)).foregroundStyle(p.ink3)
            } else if isOwn {
                Text("Your wall opens for notes once your profile is public.")
                    .font(QCFont.body(13)).foregroundStyle(p.ink3)
            }

            if entries.isEmpty {
                Text("No notes yet.").font(QCFont.body(14)).foregroundStyle(p.ink3)
            } else {
                ForEach(entries) { entry in
                    WallRow(entry: entry, reload: reload)
                    Divider().overlay(p.hairlineSoft)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Leave a note…", text: $draft, axis: .vertical)
                .font(QCFont.body(15)).foregroundStyle(p.ink)
                .lineLimit(1...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(p.surface1))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.hairline, lineWidth: 1))
            if let error { Notice(text: error, isError: true) }
            Button { Task { await post() } } label: { Text("Post note") }
                .buttonStyle(SubmitPillStyle())
                .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func post() async {
        busy = true; defer { busy = false }
        switch await ProfileService.postWallComment(profileID: profileID, body: draft) {
        case .success:
            draft = ""; error = nil; await reload()
        case .failure(let e):
            error = e.message
        }
    }
}

private struct WallRow: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    let entry: WallEntry
    let reload: () async -> Void
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if entry.authorIsPublic {
                    NavigationLink(value: Route.profile(id: entry.authorID)) {
                        Text(entry.authorName).font(QCFont.mono(10)).foregroundStyle(p.ember)
                    }
                } else {
                    Text(entry.authorName).font(QCFont.mono(10)).foregroundStyle(p.ink3)
                }
                Spacer()
                if !(entry.createdAt ?? "").isEmpty {
                    Text(Fmt.ugcDate(entry.createdAt)).font(QCFont.mono(8)).foregroundStyle(p.ink3)
                }
                rowMenu
            }
            Text(entry.body).font(QCFont.body(15)).foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showReport) {
            ReportSheet(contentType: .wall_comment, contentRef: entry.id)
        }
    }

    @ViewBuilder private var rowMenu: some View {
        if entry.canRemove {
            Button { Task { _ = await ProfileService.deleteWallComment(id: entry.id); await reload() } } label: {
                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(p.ink3)
            }
        } else if auth.isSignedIn {
            Button { showReport = true } label: {
                Image(systemName: "flag").font(.system(size: 11)).foregroundStyle(p.ink3)
            }
        }
    }
}
