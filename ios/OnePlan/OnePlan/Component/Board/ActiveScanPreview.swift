//
//  ActiveScanPreview.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//

import Foundation

// View model for the in-flight extraction surfaces (BoardView's scanning
// card, HomeView's pin-extraction banner). Moved out of BoardView so both
// screens derive it the same way.
struct ActiveScanPreview: Equatable {
    var sessionId: String
    var sourceUrl: String
    var title: String
    var thumbnailURL: URL?
    var platform: Platform
    var status: PinExtractionSessionStatus
    var pinCount: Int

    enum Platform: String {
        case tiktok, instagram, other

        var label: String {
            switch self {
            case .tiktok: return "From TikTok"
            case .instagram: return "From Instagram"
            case .other: return "From video"
            }
        }
    }

    // Returns nil when there's no in-flight or undismissed extraction.
    init?(session: PinExtractionSessionServerDto?) {
        guard let session else { return nil }

        let trimmedDescription: String? = session.videoMeta?.description
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let trimmedTitle: String? = session.videoMeta?.title
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let title = trimmedDescription ?? trimmedTitle ?? session.sourceUrl

        let host = URL(string: session.sourceUrl)?.host?.lowercased() ?? ""
        let platform: Platform
        if host.contains("instagram") {
            platform = .instagram
        } else if host.contains("tiktok") {
            platform = .tiktok
        } else {
            platform = .other
        }

        var thumbURL: URL?
        if let raw = session.videoMeta?.thumbnail {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                thumbURL = URL(string: trimmed)
            }
        }

        self.sessionId = session.id
        self.sourceUrl = session.sourceUrl
        self.title = title
        self.thumbnailURL = thumbURL
        self.platform = platform
        self.status = session.status.value1
        self.pinCount = session.pinCount
    }

    // Status-aware copy for the card header.
    var stateLabel: String {
        switch status {
        case .DONE: return String(localized: "\(pinCount) pins ready", comment: "%lld = number of extracted pins")
        case .FAILED: return String(localized: "Scan failed")
        case .CANCELLED: return String(localized: "Cancelled")
        case .QUEUED, .RUNNING: return String(localized: "Scanning video...")
        }
    }

    var resumeLabel: String {
        switch status {
        case .DONE: return String(localized: "View pins")
        case .FAILED, .CANCELLED: return String(localized: "Dismiss")
        case .QUEUED, .RUNNING: return String(localized: "Scanning")
        }
    }

    // When the scan is finished, the dismiss action is destructive — it
    // removes the session and its pins from the user's history. Surface
    // that with the danger variant + "Delete" copy.
    var cancelLabel: String {
        switch status {
        case .DONE: return String(localized: "Delete")
        case .FAILED, .CANCELLED, .QUEUED, .RUNNING: return String(localized: "Cancel")
        }
    }

    var cancelVariant: SecondaryButton.Variant {
        switch status {
        case .DONE: return .danger
        case .FAILED, .CANCELLED, .QUEUED, .RUNNING: return .dark
        }
    }
}
