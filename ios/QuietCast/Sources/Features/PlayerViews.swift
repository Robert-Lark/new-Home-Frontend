import SwiftUI

/// Upsize a Sanity image cover for large surfaces; R2 covers returned unchanged.
func upsizedCover(_ cover: String, to size: Int) -> String {
    guard cover.contains("cdn.sanity.io/images") else { return cover }
    return cover.replacingOccurrences(of: "w=\\d+&h=\\d+", with: "w=\(size)&h=\(size)", options: .regularExpression)
}

// MARK: - Compact dock (glass, follows theme) — design-tokens.md §8 player dock pill

struct PlayerDock: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let track = player.current
        HStack(spacing: 12) {
            CoverImage(urlString: track?.cover)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(p.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "Nothing playing")
                    .font(QCFont.bodyMedium(14)).foregroundStyle(p.ink).lineLimit(1)
                Text(track?.artist ?? "Quiet Cast")
                    .font(QCFont.mono(10)).tracking(0.6).foregroundStyle(p.ink2).lineLimit(1)
            }
            Spacer(minLength: 4)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(p.onEmber)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(p.ember))
            }
            .disabled(track == nil)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(p.glass))
        )
        .overlay(Capsule().stroke(p.hairline, lineWidth: 1))
        .overlay(alignment: .bottom) { progressLine }
        .shadow(color: p.shadowMix(80), radius: 30, y: 16)
        .contentShape(Capsule())
        .onTapGesture { player.isExpanded = true }
    }

    private var progressLine: some View {
        GeometryReader { geo in
            let frac = player.duration > 0 ? min(1, max(0, player.currentTime / player.duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(p.hairline).frame(height: 2)
                Capsule().fill(p.ink2).frame(width: geo.size.width * frac, height: 2)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
    }
}

// MARK: - Now playing (theme-INVARIANT over-art) — playback.md §7

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NowPlayingContent(dismiss: { dismiss() })
            .qcOverArt()
    }
}

private struct NowPlayingContent: View {
    @Environment(\.palette) private var p   // == overArt here
    @Environment(AudioPlayer.self) private var player
    var dismiss: () -> Void

    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        let track = player.current
        ZStack {
            // blurred cover backdrop + scrim
            CoverImage(urlString: track.map { upsizedCover($0.cover, to: 900) })
                .scaleEffect(1.15)
                .blur(radius: 28)
                .overlay(p.canvas.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 22) {
                grabber
                Spacer(minLength: 0)

                Recess(padding: 18) {
                    CoverImage(urlString: track.map { upsizedCover($0.cover, to: 900) })
                        .aspectRatio(1, contentMode: .fit)
                }
                .frame(maxWidth: 320)

                VStack(spacing: 8) {
                    if let catalog = track?.catalog {
                        Eyebrow("Now playing · \(catalog)", color: p.ink3)
                    } else {
                        Eyebrow("Now playing", color: p.ink3)
                    }
                    Text(track?.title ?? "")
                        .font(QCFont.display(30)).tracking(4)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(p.ink)
                    Text(track?.artist ?? "")
                        .font(QCFont.bodyItalic(17)).foregroundStyle(p.ember)
                }
                .padding(.horizontal, 24)

                scrubber
                transport

                Spacer(minLength: 0)
                if !player.upNext.isEmpty { queueList }
            }
            .padding(.bottom, 24)
        }
    }

    private var grabber: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { player.seek(to: scrubValue) }
                }
            )
            .tint(p.ember)
            HStack {
                Text(Fmt.clock(scrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text("\u{2212}" + Fmt.clock(max(0, player.duration - (scrubbing ? scrubValue : player.currentTime))))
            }
            .font(QCFont.mono(10)).foregroundStyle(p.ink3)
        }
        .padding(.horizontal, 28)
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 22)).foregroundStyle(p.ink)
            }.disabled(player.queue.isEmpty)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(p.onEmber)
                    .frame(width: 64, height: 64).background(Circle().fill(p.ember))
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 22)).foregroundStyle(p.ink)
            }.disabled(player.queue.isEmpty)
        }
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Up next", color: p.ember).padding(.horizontal, 24).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(player.upNext) { t in
                        Button { player.play(t, queue: player.queue) } label: {
                            HStack(spacing: 12) {
                                CoverImage(urlString: t.cover).frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title).font(QCFont.bodyRegular(14)).foregroundStyle(p.ink).lineLimit(1)
                                    Text(t.artist).font(QCFont.mono(9)).foregroundStyle(p.ink3).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8).padding(.horizontal, 24)
                        }
                        Divider().overlay(p.hairlineSoft)
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(p.recess.opacity(0.4))
        }
    }
}
