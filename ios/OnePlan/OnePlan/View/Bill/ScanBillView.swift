//
//  ScanBillView.swift
//  OnePlan
//
//  Created by ken on 29/3/26.
//

import AVFoundation
import PhotosUI
import SwiftUI

struct ScanBillView: View {
    @Environment(\.dismiss) private var dismiss

    var onBack: (() -> Void)? = nil
    var onImageCaptured: ((UIImage) -> Void)? = nil

    @State private var cameraManager = CameraManager()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false

    private let lensCornerRadius: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                receiptLens
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                controls
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
        }
        .background(Constants.Neutral50.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Constants.ContentB)
                }
            }
        }
        .task {
            await cameraManager.checkAuthorization()
            if cameraManager.isAuthorized {
                await cameraManager.setupSession(position: .back)
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(
                    type: Data.self
                ),
                    let image = UIImage(data: data)
                {
                    onImageCaptured?(image)
                }
                selectedPhotoItem = nil
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
    }

    private var receiptLens: some View {
        RoundedRectangle(cornerRadius: lensCornerRadius, style: .continuous)
            .fill(Constants.Neutral100)
            .overlay {
                if cameraManager.isAuthorized,
                    let session = cameraManager.getSession()
                {
                    CameraPreviewView(
                        session: session,
                        isMirrored: cameraManager.isUsingFrontCamera
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: lensCornerRadius,
                            style: .continuous
                        )
                    )
                } else {
                    GeometryReader { lensProxy in
                        Image("receiptPlaceholder")
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: min(lensProxy.size.width * 0.72, 268.84)
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .center
                            )
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: lensCornerRadius,
                    style: .continuous
                )
            )
    }

    private var controls: some View {
        HStack(spacing: 36) {
            ScanBillActionButton(
                systemName: "photo",
                action: {
                    playButtonHaptic()
                    showPhotoPicker = true
                }
            )

            captureButton

            ScanBillActionButton(
                systemName: "camera.rotate",
                action: {
                    playButtonHaptic()
                    Task { await cameraManager.toggleCamera() }
                }
            )
        }
    }

    private var captureButton: some View {
        Button {
            playButtonHaptic()
            Task { await handleCaptureButtonTap() }
        } label: {
            ZStack {
                Circle()
                    .fill(Constants.White.opacity(0.48))
                    .frame(width: 68, height: 68)

                Circle()
                    .fill(Constants.White)
                    .frame(width: 56, height: 56)
                    .shadow(
                        color: .black.opacity(0.16),
                        radius: 14,
                        x: 0,
                        y: 8
                    )

                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Constants.ContentB)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture receipt")
    }

    @MainActor
    private func handleCaptureButtonTap() async {
        guard cameraManager.isAuthorized else {
            await cameraManager.checkAuthorization()
            if cameraManager.isAuthorized {
                await cameraManager.setupSession(position: .back)
            } else if shouldOpenCameraSettings,
                let settingsURL = URL(
                    string: UIApplication.openSettingsURLString
                )
            {
                await UIApplication.shared.open(settingsURL)
            }
            return
        }

        if let image = await cameraManager.capturePhoto(
            isMirrored: cameraManager.isUsingFrontCamera
        ) {
            onImageCaptured?(image)
        }
    }

    private func playButtonHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var shouldOpenCameraSettings: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }
}

private struct ScanBillActionButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Constants.White.opacity(0.48))
                    .frame(width: 52, height: 52)

                Circle()
                    .fill(Constants.White.opacity(0.74))
                    .frame(width: 44, height: 44)

                Image(systemName: systemName)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Constants.Neutral700)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ScanBillView()
    }
}
