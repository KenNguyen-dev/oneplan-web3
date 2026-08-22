//
//  PinExtractionBanner.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//
//  Home-tab pin-extraction banner (Figma 3823:17473). Idle mode is the
//  paste-link entry ("Finding more pins / TikTok & IG videos"); when an
//  extraction session is in flight it mirrors the session state (scanning /
//  N pins ready / failed) and the trailing button resumes into
//  ProcessPinView via the launcher.
//

import SwiftUI

struct PinExtractionBanner: View {
    // Non-nil while a session is active (derived from
    // PinExtractionSessionService.activeSession by the host view).
    var preview: ActiveScanPreview?
    var isCheckingCredits = false
    let onPasteLink: () -> Void
    let onResume: (String) -> Void

    var body: some View {
        Button(action: primaryAction) {
            HStack(spacing: 12) {
                thumbnail

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topLabel)
                            .font(.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.White.opacity(0.5))
                            .lineLimit(1)

                        Text(bottomLabel)
                            .font(.beVietnamPro(15))
                            .tracking(-0.3)
                            .foregroundStyle(Constants.White)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    trailingButton
                }
                .padding(.trailing, 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.BlueBase, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.09), radius: 8.95, x: 0, y: 0)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isCheckingCredits)
    }

    private func primaryAction() {
        if let preview {
            onResume(preview.sessionId)
        } else {
            onPasteLink()
        }
    }

    private var topLabel: String {
        preview?.stateLabel ?? String(localized: "Finding more pins")
    }

    private var bottomLabel: String {
        preview?.title ?? String(localized: "TikTok & IG videos")
    }

    private var trailingButtonLabel: String {
        preview?.resumeLabel ?? String(localized: "Paste link")
    }

    private var trailingButton: some View {
        Group {
            if isCheckingCredits {
                ProgressView()
                    .tint(Constants.ContentB)
            } else {
                Text(trailingButtonLabel)
                    .font(.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 87, minHeight: 30)
        .background(Constants.White, in: Capsule())
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let url = preview?.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        fannedLogosTile
                    @unknown default:
                        fannedLogosTile
                    }
                }
            } else {
                fannedLogosTile
            }
        }
        .frame(width: 42, height: 42)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 7.82, x: 0, y: 0.98)
        .accessibilityHidden(true)
    }

    // Fanned Instagram/TikTok logos inside a white tile (Figma 3823:17474).
    private var fannedLogosTile: some View {
        ZStack {
            Image("boardInstagramLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 29, height: 29)
                .rotationEffect(.degrees(-4.5))
                .offset(x: -8, y: -8)

            Image("boardTikTokLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 31, height: 31)
                .clipShape(RoundedRectangle(cornerRadius: 7.4, style: .continuous))
                .rotationEffect(.degrees(4.62))
                .offset(x: 5, y: 8)
        }
        .frame(width: 42, height: 42)
    }
}

#Preview {
    ZStack {
        Constants.Background.ignoresSafeArea()
        PinExtractionBanner(onPasteLink: {}, onResume: { _ in })
            .padding(16)
    }
}
