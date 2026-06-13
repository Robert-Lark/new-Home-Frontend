import Foundation
import Observation
import AVFoundation
import MediaPlayer
import UIKit

/// The single persistent player (playback.md §5). AVPlayer streaming static MP3/M4A over HTTPS
/// (cdn.sanity.io + cdn.quietcast.art) — not HLS. Owns background audio, the audio session, lock-screen
/// now-playing info, remote commands, and listen-progress persistence (via LibraryStore).
@MainActor
@Observable
final class AudioPlayer {
    private(set) var current: Track?
    private(set) var queue: [Track] = []
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var isExpanded = false

    /// Wired to the favorites/listen store so progress writes update the in-memory map.
    var library: LibraryStore?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var lastWriteSeconds: Double = 0
    private var resumeTarget: (id: String, seconds: Double)?
    private var interruptedWhilePlaying = false

    private static let writeEverySeconds: Double = 20
    private static let minResumeSeconds: Double = 10

    init() {
        configureSession()
        observePlayer()
        observeSystemNotifications()
        setupRemoteCommands()
    }

    var hasTrack: Bool { current != nil }

    // MARK: - Public control

    /// Play a track. `queue` REPLACES the current queue when provided; a single-track play
    /// (mix / profile song) clears the queue so prev/next don't operate over a stale list
    /// (deliberate divergence from the web's stale-queue quirk, playback.md §5).
    func play(_ track: Track, queue newQueue: [Track]? = nil) {
        if let newQueue, !newQueue.isEmpty {
            queue = newQueue.filter { !$0.src.isEmpty && !$0.id.isEmpty }
        } else {
            queue = []
        }
        load(track, autoPlay: true)
    }

    func togglePlayPause() {
        guard current != nil else { return }
        if isPlaying { pause() } else { resumePlayback() }
    }

    func pause() {
        player.pause()
        flushProgress()
    }

    func resumePlayback() {
        guard current != nil else { return }
        activateSession()
        player.play()
    }

    func next() { playAt(1) }
    func previous() { playAt(-1) }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration.isFinite ? duration : seconds))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateNowPlayingElapsed()
    }

    /// "Up next" rotated relative to current: the rest, then the ones before (current excluded).
    var upNext: [Track] {
        guard let id = current?.id, let i = queue.firstIndex(where: { $0.id == id }) else { return queue }
        return Array(queue[(i + 1)...] + queue[..<i])
    }

    // MARK: - Loading

    private func load(_ track: Track, autoPlay: Bool) {
        // flush the outgoing track's progress before switching
        flushProgress()
        guard let url = URL(string: track.src) else { return }

        current = track
        currentTime = 0
        duration = 0
        lastWriteSeconds = 0
        resumeTarget = nil

        let item = AVPlayerItem(url: url)
        observeItem(item)
        player.replaceCurrentItem(with: item)

        // Resume decision (playback.md §5): seek iff saved status=='playing' && progress>10 && <97% dur.
        Task { [weak self] in
            guard let self, let progress = await self.library?.fetchProgress(ref: track.id) else { return }
            if progress.status == "playing", Double(progress.progressSeconds) > Self.minResumeSeconds {
                self.resumeTarget = (track.id, Double(progress.progressSeconds))
            }
        }

        activateSession()
        if autoPlay { player.play() }
        loadArtwork(for: track)
        updateNowPlayingInfo()
    }

    private func playAt(_ delta: Int) {
        guard !queue.isEmpty else { return }   // empty queue → stop at end / no-op
        let id = current?.id
        let i = queue.firstIndex(where: { $0.id == id }) ?? -1
        let next = (i + delta + queue.count) % queue.count
        load(queue[next], autoPlay: true)
    }

    // MARK: - Observation

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                self?.updateNowPlayingInfo()
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard item.status == .readyToPlay else { return }
                let d = item.duration.seconds
                if d.isFinite, d > 0 {
                    self?.duration = d
                    self?.applyResumeIfNeeded(duration: d)
                    self?.updateNowPlayingInfo()
                }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.playerDidFinish() }
        }
    }

    private func applyResumeIfNeeded(duration: Double) {
        guard let target = resumeTarget, target.id == current?.id else { return }
        if target.seconds > 0, target.seconds < duration * 0.97 {
            player.seek(to: CMTime(seconds: target.seconds, preferredTimescale: 600))
            currentTime = target.seconds
            lastWriteSeconds = target.seconds
        }
        resumeTarget = nil
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        updateNowPlayingElapsed()
        if isPlaying, seconds - lastWriteSeconds >= Self.writeEverySeconds {
            lastWriteSeconds = seconds
            writeProgress(seconds: seconds, duration: duration)
        }
    }

    private func playerDidFinish() {
        if let track = current, duration > 0 {
            writeProgress(seconds: duration, duration: duration)   // ratio 1.0 → 'played'
            _ = track
        }
        playAt(1)
    }

    // MARK: - Progress persistence

    private func flushProgress() {
        guard current != nil, currentTime > 0 else { return }
        writeProgress(seconds: currentTime, duration: duration)
    }

    private func writeProgress(seconds: Double, duration: Double) {
        guard let ref = current?.id else { return }
        Task { [weak self] in await self?.library?.recordProgress(ref: ref, progressSeconds: seconds, durationSeconds: duration) }
    }

    // MARK: - Audio session + interruptions

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observeSystemNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            interruptedWhilePlaying = isPlaying
            player.pause()
            flushProgress()
        case .ended:
            if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume),
               interruptedWhilePlaying {
                activateSession()
                player.play()
            }
            interruptedWhilePlaying = false
        @unknown default: break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headphones/Bluetooth removed → pause (don't blast through the speaker).
        if reason == .oldDeviceUnavailable {
            player.pause()
            flushProgress()
        }
    }

    // MARK: - Now playing / remote commands

    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resumePlayback() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayPause() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let catalog = track.catalog { info[MPMediaItemPropertyAlbumTitle] = catalog }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let art = artworkCache[track.id] { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: Track) {
        if artworkCache[track.id] != nil { updateNowPlayingInfo(); return }
        guard let url = artworkURL(track.cover) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                self?.artworkCache[track.id] = art
                self?.updateNowPlayingInfo()
            }
        }
    }

    /// Bump Sanity image covers to a lock-screen-friendly size; R2 covers used as-is.
    private func artworkURL(_ cover: String) -> URL? {
        guard !cover.isEmpty else { return nil }
        if cover.contains("cdn.sanity.io/images") {
            let bigger = cover.replacingOccurrences(
                of: "w=\\d+&h=\\d+", with: "w=600&h=600", options: .regularExpression)
            return URL(string: bigger)
        }
        return URL(string: cover)
    }
}
