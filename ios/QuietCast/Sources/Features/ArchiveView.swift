import SwiftUI

/// Archive — the chronological ledger (archive.astro). Episodes grouped by exact YYYY-MM-DD
/// (within a day, cat desc); a continuous newest-first year range, empty years included. A day
/// with shows links to its newest-cat show; the dot reflects listen state.
struct ArchiveView: View {
    @Environment(\.palette) private var p
    @Environment(LibraryStore.self) private var library
    @State private var episodes: [Episode] = []
    @State private var loaded = false

    private var dated: [Episode] { episodes.filter { $0.airDate != nil } }

    private var byDay: [String: [Episode]] {
        Dictionary(grouping: dated, by: { $0.airDate! }).mapValues { $0.sorted { $0.cat > $1.cat } }
    }

    private var years: [Int] {
        let ys = dated.compactMap { $0.year.flatMap(Int.init) }
        guard let lo = ys.min(), let hi = ys.max() else { return [] }
        return Array(lo...hi).reversed()
    }

    private var totalTracks: Int { episodes.reduce(0) { $0 + $1.tracklist.count } }

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(years, id: \.self) { year in
                        yearSection(year)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 140)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Transmission ledger")
            DisplayTitle(text: "Archive", size: 34, tracking: 3)
            if !years.isEmpty {
                Text("\(dated.count) shows · \(years.last!)–\(years.first!) · \(totalTracks) tracks")
                    .font(QCFont.mono(10)).tracking(0.5).foregroundStyle(p.ink3)
            }
        }
        .padding(.top, 8)
    }

    private func yearSection(_ year: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(year)).font(QCFont.display(26)).foregroundStyle(p.ink2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 18) {
                ForEach(1...12, id: \.self) { month in
                    monthCell(year: year, month: month)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func monthCell(year: Int, month: Int) -> some View {
        let days = daysInMonth(year, month)
        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.monthAbbr[month - 1]).font(QCFont.mono(9)).foregroundStyle(p.ink3)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(9), spacing: 3), count: 7), spacing: 3) {
                ForEach(1...days, id: \.self) { day in
                    dayDot(year: year, month: month, day: day)
                }
            }
        }
    }

    @ViewBuilder private func dayDot(year: Int, month: Int, day: Int) -> some View {
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        if let shows = byDay[key], let newest = shows.first {
            let st = library.state(for: newest.slug)
            NavigationLink(value: Route.show(slug: newest.slug)) {
                Circle()
                    .fill(st == .done ? p.ember.opacity(0.6) : p.ember)
                    .frame(width: 7, height: 7)
                    .overlay(st == .inProgress ? Circle().stroke(p.ember, lineWidth: 1).frame(width: 9, height: 9) : nil)
            }
            .buttonStyle(.plain)
        } else {
            Circle().fill(p.hairline).frame(width: 7, height: 7)
        }
    }

    private static let monthAbbr = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    private func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private func load() async {
        if loaded { return }
        episodes = (try? await SanityService.shared.episodes()) ?? []
        loaded = true
    }
}
