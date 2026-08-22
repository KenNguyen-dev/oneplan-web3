//
//  VoiceRecordingComponents.swift
//  OnePlan
//
//  Shared voice recording UI components used by PlanFormView.
//

import SwiftUI

struct RecordButton: View {
    let hasRecording: Bool
    let action: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Constants.White)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(
                                systemName: hasRecording ? "checkmark" : "mic.fill"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Constants.BlueBase)
                        }

                    Text(hasRecording ? String(localized: "Recorded") : String(localized: "Record"))
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.White)
                }
                .padding(.leading, 5)
                .padding(.trailing, 10)
                .padding(.vertical, 5)
                .background(hasRecording ? Constants.ContentB : Constants.BlueBase)
                .cornerRadius(999)
            }
            .buttonStyle(.plain)

            if hasRecording, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                        .frame(width: 30, height: 30)
                        .background(Color(red: 0.99, green: 0.91, blue: 0.91))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RecordingModalOverlay: View {
    let planName: String
    let audioManager: AudioRecordingManager
    let onClose: () -> Void
    let onStop: () -> Void

    var body: some View {
        ZStack {
            RecordingCard(
                planName: planName,
                audioManager: audioManager,
                onStop: onStop
            )
            .padding(.horizontal)
            .padding(.top, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(Constants.White)

                    Circle()
                        .stroke(Constants.White.opacity(0.4), lineWidth: 1)

                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Constants.ContentM)
                }
                .frame(width: 32, height: 32)
                .shadow(
                    color: Constants.Black.opacity(0.2),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(.plain)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topTrailing
            )
            .padding(.top, 29)
            .padding(.trailing, 6)
        }
    }
}

struct RecordingCard: View {
    let planName: String
    let audioManager: AudioRecordingManager
    let onStop: () -> Void

    private var durationText: String {
        let seconds = Int(audioManager.recordingDuration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(planName)
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)

                Text(audioManager.isRecording ? durationText : "Say something")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentM)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Constants.DividerStroke)
                .frame(height: 1)

            Spacer(minLength: 0)

            RecordingWaveform(levels: audioManager.levelSamples)
                .padding(.horizontal, 12)

            Spacer(minLength: 0)

            StopRecordingButton(action: onStop)
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 341)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

struct RecordingWaveform: View {
    let levels: [Float]
    private let barCount = 51

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? levels[index] : 0
                let height = max(8, CGFloat(level) * 58)
                Capsule(style: .continuous)
                    .fill(Constants.ContentL.opacity(0.9))
                    .frame(width: 2, height: height)
                    .animation(.easeOut(duration: 0.08), value: height)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StopRecordingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.76, green: 0.9, blue: 1),
                                Constants.BlueBase,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(Constants.White, lineWidth: 1.7)
                    }
                    .shadow(
                        color: Color(red: 0.58, green: 0.82, blue: 1).opacity(
                            0.45
                        ),
                        radius: 12,
                        x: 0,
                        y: 6
                    )

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Constants.White)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
    }
}
