//
//  PlanVoicePlaybackService.swift
//  OnePlan
//

import AVFoundation
import Foundation

@MainActor
@Observable
final class PlanVoicePlaybackService {
    var isLoading = false
    var isPlaying = false
    var error: String?

    private let storageService = StorageUploadService()
    private var player: AVPlayer?
    private var currentSourceKey: String?
    private var endObserver: NSObjectProtocol?

    func togglePlayback(for source: String) async {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isPlaying, currentSourceKey == trimmed {
            pause()
            return
        }

        do {
            let preparedPlayer = try await preparePlayer(for: trimmed)
            preparedPlayer.play()
            isPlaying = true
            error = nil
        } catch {
            self.error = String(localized: "Unable to play voice message.")
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        isPlaying = false
    }

    func clearError() {
        error = nil
    }

    private func preparePlayer(for source: String) async throws -> AVPlayer {
        if let player, currentSourceKey == source {
            return player
        }

        isLoading = true
        defer { isLoading = false }

        let playableURL = try await resolvePlayableURL(from: source)
        let newPlayer = AVPlayer(url: playableURL)
        player = newPlayer
        currentSourceKey = source
        observeDidFinish(for: newPlayer)
        return newPlayer
    }

    private func resolvePlayableURL(from source: String) async throws -> URL {
        if let directURL = URL(string: source),
           let scheme = directURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return directURL
        }

        return try await storageService.imageURL(for: source)
    }

    private func observeDidFinish(for player: AVPlayer) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
            }
        }
    }
}
