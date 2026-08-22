//
//  ShareViewController.swift
//  ShareExtension
//
//  No-UI Share Extension principal class. When the user shares an Instagram /
//  TikTok link into OnePlan, this:
//    1. pulls the URL (or plain text containing one) from the shared item,
//    2. validates the host with the SHARED `SupportedVideoLink` helper,
//    3. writes the link to the App Group (`SharedExtractionStore`),
//    4. foregrounds the host app via the responder-chain open trick,
//    5. completes the request (dismisses) — no compose UI, "bounce" feel.
//
//  There is intentionally no storyboard: `NSExtensionPrincipalClass` in the
//  extension's Info.plist points straight at this class. Delete the generated
//  `MainInterface.storyboard` from the target.
//
//  `SupportedVideoLink.swift` and `SharedExtractionStore.swift` (in the app's
//  Services folder) are also members of this target — both Foundation-only.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedItem()
    }

    private func handleSharedItem() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = item.attachments
        else {
            finish()
            return
        }

        // Prefer a URL attachment; fall back to plain text that contains a URL
        // (some apps share the link as text rather than a typed URL).
        if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            load(provider, type: UTType.url.identifier)
        } else if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            load(provider, type: UTType.plainText.identifier)
        } else {
            finish()
        }
    }

    private func load(_ provider: NSItemProvider, type: String) {
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
            let raw = (item as? URL)?.absoluteString ?? (item as? String)
            self?.process(raw)
        }
    }

    private func process(_ raw: String?) {
        // Off the main thread (loadItem callback). Validate, persist, then hop
        // to main for the UIKit open + dismiss.
        guard let raw, let link = SupportedVideoLink.extract(from: raw) else {
            // Not an IG/TikTok link — quietly dismiss without opening the app.
            // (We share from inside IG/TikTok, so this is an edge case.)
            DispatchQueue.main.async { [weak self] in self?.finish() }
            return
        }

        SharedExtractionStore.write(link)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let url = URL(string: "oneplan://board/extract") {
                self.openHostApp(url)
            }
            self.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: - Open host app (responder-chain walk)

    // App extensions cannot use `UIApplication.open` directly (it is unavailable
    // in the app-extension context). Walk the responder chain for an object that
    // responds to the legacy `openURL:` selector — at runtime that is the host
    // `UIApplication`. This is the widely-shipped technique; it carries a small
    // App Review risk and may be refused on a future iOS. That's acceptable
    // here: the App Group write already happened, so the app picks the link up
    // on its next foreground regardless (see SharedExtractionStore + the
    // didBecomeActive fallback in OnePlanApp).
    @objc @discardableResult
    func openURL(_ url: URL) -> Bool { false }

    private func openHostApp(_ url: URL) {
        let selector = #selector(openURL(_:))
        var responder: UIResponder? = self
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}
