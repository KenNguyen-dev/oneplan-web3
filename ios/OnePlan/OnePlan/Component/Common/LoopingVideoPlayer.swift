//
//  LoopingVideoPlayer.swift
//  OnePlan
//

import AVFoundation
import SwiftUI

struct LoopingVideoPlayer: UIViewRepresentable {
    let assetName: String

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(assetName: assetName)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

final class LoopingPlayerUIView: UIView {
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init(assetName: String) {
        super.init(frame: .zero)
        setupPlayer(assetName: assetName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPlayer(assetName: String) {
        guard let dataAsset = NSDataAsset(name: assetName) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(assetName).mp4")

        if !FileManager.default.fileExists(atPath: tempURL.path) {
            try? dataAsset.data.write(to: tempURL)
        }

        let asset = AVAsset(url: tempURL)
        let playerItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        queuePlayer.isMuted = true

        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)

        self.player = queuePlayer
        self.playerLooper = looper
        self.playerLayer = layer

        queuePlayer.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}
