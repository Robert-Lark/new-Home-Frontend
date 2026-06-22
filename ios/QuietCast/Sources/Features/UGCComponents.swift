import SwiftUI

/// Renders parsed markdown blocks with the web's .prose styling (ugc.md §5 reference).
struct MarkdownView: View {
    @Environment(\.palette) private var p
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                switch block {
                case .heading2(let s):
                    Text(s).font(QCFont.display(24)).textCase(.uppercase).tracking(2).foregroundStyle(p.ink)
                case .heading3(let s):
                    Text(s).font(QCFont.display(19)).textCase(.uppercase).tracking(2).foregroundStyle(p.ink)
                case .paragraph(let lines):
                    Text(joined(lines)).font(QCFont.body(17)).lineSpacing(6).foregroundStyle(p.ink2)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(p.ember)
                                Text(item).font(QCFont.body(17)).foregroundStyle(p.ink2)
                            }
                        }
                    }
                case .quote(let lines):
                    Text(joined(lines))
                        .font(QCFont.bodyItalic(19)).foregroundStyle(p.stone)
                        .padding(.leading, 16)
                        .overlay(alignment: .leading) { Rectangle().fill(p.ember).frame(width: 2) }
                }
            }
        }
        .tint(p.ember)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func joined(_ lines: [AttributedString]) -> AttributedString {
        var out = AttributedString()
        for (i, line) in lines.enumerated() {
            if i > 0 { out.append(AttributedString("\n")) }
            out.append(line)
        }
        return out
    }
}

/// Owner-only visibility toggle + removed badge (VisibilityToggle.astro). The author flips
/// published⇄private; a removed row is curator-locked and only shows the takedown notice.
struct OwnerVisibilityControl: View {
    @Environment(\.palette) private var p
    let table: UGCService.VisibilityTable
    let id: String
    @Binding var status: String
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status == "removed" {
                StatusBadge(text: "removed by the curator")
                Text("Taken down by the curator — reply to the takedown notice if you think that's wrong.")
                    .font(QCFont.body(13)).foregroundStyle(p.ink3)
            } else {
                HStack(spacing: 10) {
                    Eyebrow(status == "published" ? "Public" : "Private — only you")
                    Spacer()
                    Button {
                        Task { await toggle() }
                    } label: {
                        Text(status == "published" ? "Make private" : "Publish")
                    }
                    .buttonStyle(GhostPillStyle())
                    .frame(width: 160)
                    .disabled(busy)
                }
                if let message { Notice(text: message, isError: true) }
            }
        }
        .padding(.vertical, 6)
    }

    private func toggle() async {
        busy = true; defer { busy = false }
        let next = status != "published"
        switch await UGCService.setVisibility(table: table, id: id, published: next) {
        case .ok: status = next ? "published" : "private"; message = nil
        case .locked: status = "removed"; message = "This piece was removed and can't be edited."
        case .error(let m): message = m
        }
    }
}

/// Non-owner moderation affordances: report + block (App Store UGC guideline 1.2).
struct ModerationMenu: View {
    @Environment(\.palette) private var p
    let contentType: UGCService.ContentType
    let contentRef: String
    let authorID: String?
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var toast: String?

    var body: some View {
        Menu {
            Button("Report", systemImage: "flag") { showReport = true }
            if authorID != nil {
                Button("Block this user", systemImage: "hand.raised", role: .destructive) { showBlockConfirm = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(p.ink2)
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(contentType: contentType, contentRef: contentRef)
        }
        .alert("Block this user?", isPresented: $showBlockConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                if let id = authorID { Task { _ = await ProfileService.blockUser(id) } }
            }
        } message: {
            Text("They won't be able to message you or post on your wall, and you won't see their wall notes.")
        }
    }
}

struct ReportSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let contentType: UGCService.ContentType
    let contentRef: String
    @State private var reason = ""
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        ThemedScreen {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow("Report content")
                Text("Tell the curator what's wrong. They'll take a look.")
                    .font(QCFont.body(15)).foregroundStyle(p.ink2)
                TextEditor(text: $reason)
                    .font(QCFont.body(15))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(p.surface1))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.hairline, lineWidth: 1))
                if let result { Notice(text: result) }
                Button {
                    Task { await submit() }
                } label: { Text("Send report") }
                    .buttonStyle(SubmitPillStyle())
                    .disabled(busy || reason.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(20)
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        busy = true; defer { busy = false }
        switch await UGCService.report(contentType: contentType, contentRef: contentRef, reason: reason) {
        case .success(let m): result = m; try? await Task.sleep(for: .seconds(1)); dismiss()
        case .failure(let e): result = e.message
        }
    }
}

/// Common detail header: eyebrow + title + byline.
struct DetailHeader: View {
    @Environment(\.palette) private var p
    let eyebrow: String?
    let title: String
    let authorID: String
    let authorName: String
    let authorIsPublic: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow { Eyebrow(eyebrow) }
            DisplayTitle(text: title, size: 28, tracking: 2)
            Byline(userID: authorID, name: authorName, isPublic: authorIsPublic)
        }
    }
}
