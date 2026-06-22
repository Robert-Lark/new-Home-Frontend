import SwiftUI

/// Interviews — episodes with at least one Q&A pair, sorted cat ASC (interviews.astro). "Interview"
/// is not a type, it's any episode with qa.length > 0.
struct InterviewsView: View {
    @Environment(\.palette) private var p
    @State private var episodes: [Episode] = []
    @State private var loaded = false

    private var interviews: [Episode] {
        episodes.filter { !$0.qa.isEmpty }.sorted { $0.cat < $1.cat }
    }

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("In conversation")
                        DisplayTitle(text: "Interviews", size: 34, tracking: 3)
                    }
                    .padding(.bottom, 4)

                    if interviews.isEmpty && loaded {
                        Notice(text: "No interviews loaded.")
                    }
                    ForEach(interviews) { ep in
                        NavigationLink(value: Route.show(slug: ep.slug)) { row(ep) }
                            .buttonStyle(.plain)
                        Divider().overlay(p.hairlineSoft)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 140)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ ep: Episode) -> some View {
        HStack(spacing: 14) {
            CoverImage(urlString: Sanity.sizedCover(ep.coverURL, 200))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(ep.catLabel)
                Text(ep.title).font(QCFont.displayRegular(20)).foregroundStyle(p.ink).lineLimit(1)
                Text(ep.artist).font(QCFont.bodyItalic(14)).foregroundStyle(p.ink2).lineLimit(1)
            }
            Spacer()
            Text("\(ep.qa.count) Q").font(QCFont.mono(9)).foregroundStyle(p.ink3)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        if loaded { return }
        episodes = (try? await SanityService.shared.episodes()) ?? []
        loaded = true
    }
}
