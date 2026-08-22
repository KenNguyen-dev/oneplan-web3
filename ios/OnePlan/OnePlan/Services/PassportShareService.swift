//
//  PassportShareService.swift
//  OnePlan
//

import SwiftUI
import UIKit

/// Renders the passport card to a PNG and routes it to share destinations.
@MainActor
enum PassportShareService {
    /// Renders the `.render` variant (no chips / share row, static strip).
    static func renderCardImage(
        summary: PassportSummaryDto?,
        fallbackDisplayName: String
    ) -> UIImage? {
        let card = PassportCard(
            summary: summary,
            fallbackDisplayName: fallbackDisplayName,
            variant: .render
        )
        .frame(width: 360)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Posts the image to Instagram Stories via the pasteboard handoff.
    /// Returns false when Instagram is not installed (caller should fall back
    /// to the system share sheet).
    ///
    /// Note: Meta documents `source_application` as a Meta App ID; passing the
    /// bundle id works on current Instagram builds without a registered app.
    static func shareToInstagramStories(_ image: UIImage) -> Bool {
        let bundleId = Bundle.main.bundleIdentifier ?? "lumilabs.oneplan"
        guard
            let url = URL(string: "instagram-stories://share?source_application=\(bundleId)"),
            UIApplication.shared.canOpenURL(url),
            let pngData = image.pngData()
        else {
            return false
        }

        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": pngData]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        UIApplication.shared.open(url)
        return true
    }
}
