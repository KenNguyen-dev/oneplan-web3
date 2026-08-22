import CoreImage
import PhotosUI
import SwiftUI

/// Full screen VietQR scanner for paying a merchant from the trip vault.
///
/// The payload is decoded on device by `VietQRDecoder` before anything is sent,
/// so a code that is not a Vietnamese bank transfer is rejected here rather than
/// round-tripping through the server.
///
/// A code can also come from a photo, which is what the design asks for — people
/// are sent a QR as often as they stand in front of one — and is also the only
/// way to exercise this screen in the simulator, which has no camera.
struct VaultScanQRView: View {
    var onScanned: (VietQRPayload, String) -> Void
    var onCancel: () -> Void = {}

    @State private var scanner = QRScannerManager()
    @State private var rejectedMessage: String?
    @State private var pickedPhoto: PhotosPickerItem?

    /// 174.65pt square in the design.
    private static let frameSize: CGFloat = 175

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if scanner.isAuthorized, let session = scanner.getSession() {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            }

            // A fixed frame rather than one tracking the detected code's bounds:
            // AVCaptureMetadataOutput reports those, but QRScannerManager only
            // surfaces the payload string, and plumbing bounds through for a
            // highlight that appears for one frame is not worth the coupling.
            scanFrame

            VStack {
                header
                Spacer()
                if let rejectedMessage {
                    Text(rejectedMessage)
                        .font(Font.beVietnamPro(14))
                        .foregroundStyle(Constants.White)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.bottom, 48)
                        .transition(.opacity)
                }
            }
        }
        .task {
            await scanner.startScanning { payload in
                handle(payload)
            }
        }
        .onDisappear { scanner.stopSession() }
        .onChange(of: pickedPhoto) { _, item in
            Task { await readCode(from: item) }
        }
    }

    /// Two separate controls rather than one pill, as the design draws them:
    /// a 32pt square holding the arrow, then a 61pt pill holding the word.
    private var header: some View {
        HStack(spacing: 5) {
            Button(action: onCancel) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Constants.White)
                    .frame(width: 32, height: 32)
            }
            .vaultHeaderChip(overCamera: true)
            .accessibilityLabel("Back")

            Button(action: onCancel) {
                Text("Back")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.3)
                    .foregroundStyle(Constants.White)
                    .frame(width: 61, height: 34)
            }
            .vaultHeaderChip(overCamera: true)

            Spacer()

            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Constants.White)
                    .frame(width: 36, height: 36)
            }
            .vaultHeaderChip(cornerRadius: 18, overCamera: true)
            .accessibilityLabel("Choose a code from your photos")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var scanFrame: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(VaultPalette.scanFrame, lineWidth: 3)
            .frame(width: Self.frameSize, height: Self.frameSize)
            .shadow(color: VaultPalette.scanFrame.opacity(0.5), radius: 12)
            .overlay {
                if !scanner.isAuthorized {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 26))
                        Text("Allow camera access, or pick a code from your photos")
                            .font(Font.beVietnamPro(13))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Constants.White.opacity(0.7))
                    .padding(.horizontal, 12)
                }
            }
    }

    /// Pulls a QR out of a still image.
    ///
    /// Takes the first code found. An image with several is ambiguous, and
    /// guessing which one was meant is worse than asking for a tighter crop.
    private func readCode(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = CIImage(data: data)
        else {
            await reject("Could not read that image")
            return
        }

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: image) as? [CIQRCodeFeature]
        guard let payload = features?.first?.messageString, !payload.isEmpty else {
            await reject("No QR code in that image")
            return
        }
        handle(payload)
    }

    private func handle(_ payload: String) {
        do {
            let decoded = try VietQRDecoder.decode(
                payload.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            scanner.stopSession()
            onScanned(decoded, payload)
        } catch {
            // Keep scanning: the user is most likely pointing at a non-payment
            // code, and closing the camera would make them start over.
            Task { await reject("That is not a Vietnamese payment code") }
        }
    }

    @MainActor
    private func reject(_ message: String) async {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        withAnimation { rejectedMessage = message }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { rejectedMessage = nil }
    }
}
