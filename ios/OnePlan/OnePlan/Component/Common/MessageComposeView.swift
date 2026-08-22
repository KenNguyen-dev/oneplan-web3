//
//  MessageComposeView.swift
//  OnePlan
//

import MessageUI
import SwiftUI

/// Wraps MFMessageComposeViewController to share an image over iMessage/SMS.
/// Callers must check `MessageComposeView.canSendImage` before presenting.
struct MessageComposeView: UIViewControllerRepresentable {
    let image: UIImage
    let filename: String
    @Environment(\.dismiss) private var dismiss

    static var canSendImage: Bool {
        MFMessageComposeViewController.canSendText()
            && MFMessageComposeViewController.canSendAttachments()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        if let pngData = image.pngData() {
            controller.addAttachmentData(
                pngData,
                typeIdentifier: "public.png",
                filename: filename
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: () -> Void

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            dismiss()
        }
    }
}

/// Minimal UIActivityViewController wrapper used as the share fallback when a
/// dedicated destination (Instagram, Messages) is unavailable.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
