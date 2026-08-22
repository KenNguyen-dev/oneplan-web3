//
//  SheetOpeningSoundPlayer.swift
//  OnePlan
//

import AVFoundation
import UIKit

@MainActor
final class SheetOpeningSoundPlayer {
    static let shared = SheetOpeningSoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

    func playOpeningSheet() {
        playAsset(named: "openingSheetShoud")
    }

    func playNavigateFromSheet() {
        playAsset(named: "navigateFromSheetSound")
    }

    func play() {
        playOpeningSheet()
    }

    private func playAsset(named assetName: String) {
        if players[assetName] == nil {
            preparePlayerIfNeeded(for: assetName)
        }

        guard let player = players[assetName] else { return }
        player.currentTime = 0
        player.play()
    }

    private func preparePlayerIfNeeded(for assetName: String) {
        guard let dataAsset = NSDataAsset(name: assetName) else { return }

        do {
            let newPlayer = try AVAudioPlayer(data: dataAsset.data)
            newPlayer.prepareToPlay()
            players[assetName] = newPlayer
        } catch {
            #if DEBUG
            print("SheetOpeningSoundPlayer failed to initialize \(assetName): \(error)")
            #endif
        }
    }
}
