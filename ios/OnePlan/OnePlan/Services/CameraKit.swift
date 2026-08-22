//
//  CameraKit.swift
//  pocket-check
//
//  Created by ken on 4/2/26.
//

import AVFoundation
import SwiftUI

// MARK: - Camera Manager
@MainActor
@Observable
final class CameraManager {
    var isAuthorized = false
    var capturedImage: UIImage?
    var isUsingFrontCamera = false
    var error: CameraError?

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentCameraInput: AVCaptureDeviceInput?
    private var isCapturing = false

    // Serial queue used for all session configuration and start/stop to
    // prevent calling `startRunning` while `beginConfiguration` is active.
    private let sessionQueue = DispatchQueue(label: "com.ken.pocket-check.camera.session")

    enum CameraError: Error, LocalizedError {
        case noCameraAvailable
        case setupFailed
        case captureFailed
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .noCameraAvailable:
                "No camera available on this device"
            case .setupFailed:
                "Failed to set up camera"
            case .captureFailed:
                "Failed to capture photo"
            case .notAuthorized:
                "Camera access not authorized"
            }
        }
    }

    func checkAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
            error = .notAuthorized
        }
    }

    func getSession() -> AVCaptureSession? {
        captureSession
    }

    func setupSession(position: AVCaptureDevice.Position = .back) async {
        guard isAuthorized else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard
            let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position
            )
        else {
            error = .noCameraAvailable
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCapturePhotoOutput()

            // Keep session reference and perform adding inputs/outputs and
            // starting the session on the dedicated serial queue so that
            // configuration and start/stop do not race with each other.
            captureSession = session

            sessionQueue.async { [weak self, session] in
                if session.canAddInput(input) {
                    session.addInput(input)
                }

                if session.canAddOutput(output) {
                    session.addOutput(output)
                }

                session.startRunning()

                // Update actor-isolated state back on the main actor
                DispatchQueue.main.async {
                    self?.currentCameraInput = input
                    self?.photoOutput = output
                    self?.isUsingFrontCamera = (position == .front)
                }
            }
        } catch {
            self.error = .setupFailed
        }
    }

    func toggleCamera() async {
        guard let session = captureSession,
            let currentInput = currentCameraInput
        else { return }

        let newPosition: AVCaptureDevice.Position =
            isUsingFrontCamera ? .back : .front

        guard
            let newCamera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: newPosition
            )
        else {
            return
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: newCamera)

            // Perform configuration on the serial session queue so it's
            // ordered with start/stop operations and avoids the race that
            // triggers the warning about calling startRunning between
            // beginConfiguration/commitConfiguration.
            sessionQueue.async { [weak self, session] in
                session.beginConfiguration()
                session.removeInput(currentInput)

                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    session.commitConfiguration()

                    // Update actor-isolated state back on the main actor
                    DispatchQueue.main.async {
                        self?.currentCameraInput = newInput
                        self?.isUsingFrontCamera.toggle()
                    }
                } else {
                    // Fall back to previous input
                    session.addInput(currentInput)
                    session.commitConfiguration()
                }
            }
        } catch {
            // Keep current camera if switch fails
        }
    }

    func capturePhoto(isMirrored: Bool = false) async -> UIImage? {
        guard let photoOutput, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        return await withCheckedContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            if let connection = photoOutput.connection(with: .video) {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = isMirrored
            }
            let delegate = PhotoCaptureDelegate { image in
                continuation.resume(returning: image)
            }

            // Store delegate with a unique key to prevent deallocation
            // and avoid overwriting a previous in-flight delegate
            let key = Unmanaged.passUnretained(delegate).toOpaque()
            objc_setAssociatedObject(
                photoOutput,
                key,
                delegate,
                .OBJC_ASSOCIATION_RETAIN
            )
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func stopSession() {
        sessionQueue.async { [captureSession] in
            captureSession?.stopRunning()
        }
    }
}

// MARK: - QR Scanner Manager
@MainActor
@Observable
final class QRScannerManager {
    var isAuthorized = false
    var isRunning = false
    var lastScannedCode: String?
    var error: QRScannerError?

    private var captureSession: AVCaptureSession?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var cameraInput: AVCaptureDeviceInput?
    private var metadataDelegate: QRCodeMetadataDelegate?
    private var onCodeScanned: ((String) -> Void)?

    private var lastDeliveredCode: String?
    private var lastDeliveredAt = Date.distantPast
    private let dedupCooldown: TimeInterval = 1.0

    private let sessionQueue = DispatchQueue(
        label: "com.ken.oneplan.qrscanner.session"
    )

    enum QRScannerError: Error, LocalizedError {
        case noCameraAvailable
        case setupFailed
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .noCameraAvailable:
                "No camera is available on this device."
            case .setupFailed:
                "Unable to set up the scanner camera."
            case .notAuthorized:
                "Camera access is required to scan QR codes."
            }
        }
    }

    func getSession() -> AVCaptureSession? {
        captureSession
    }

    func checkAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            error = nil
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            error = isAuthorized ? nil : .notAuthorized
        default:
            isAuthorized = false
            error = .notAuthorized
        }
    }

    func startScanning(onCodeScanned: @escaping (String) -> Void) async {
        self.onCodeScanned = onCodeScanned

        if !isAuthorized {
            await checkAuthorization()
        }

        guard isAuthorized else { return }

        if captureSession == nil {
            await setupSession()
        }

        startSession()
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, let captureSession = self.captureSession else { return }
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, let captureSession = self.captureSession else { return }
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = captureSession.isRunning
            }
        }
    }

    private func setupSession() async {
        guard isAuthorized else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard
            let camera = preferredScannerCamera()
        else {
            error = .noCameraAvailable
            return
        }

        do {
            try configureCameraForScanning(camera)

            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureMetadataOutput()
            let delegate = QRCodeMetadataDelegate { [weak self] code in
                self?.handleDetected(code: code)
            }

            output.setMetadataObjectsDelegate(delegate, queue: .main)
            captureSession = session
            metadataDelegate = delegate

            sessionQueue.async { [weak self, session] in
                guard let self else { return }
                session.beginConfiguration()

                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.error = .setupFailed
                    }
                    return
                }

                session.addInput(input)
                session.addOutput(output)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()

                if !session.isRunning {
                    session.startRunning()
                }

                DispatchQueue.main.async {
                    self.cameraInput = input
                    self.metadataOutput = output
                    self.isRunning = session.isRunning
                    self.error = nil
                }
            }
        } catch {
            self.error = .setupFailed
        }
    }

    private func preferredScannerCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )

        return discoverySession.devices.first
    }

    private func configureCameraForScanning(_ camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }

        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        } else if camera.isFocusModeSupported(.autoFocus) {
            camera.focusMode = .autoFocus
        }

        if camera.isAutoFocusRangeRestrictionSupported {
            camera.autoFocusRangeRestriction = .near
        }

        if camera.isSmoothAutoFocusSupported {
            camera.isSmoothAutoFocusEnabled = true
        }

        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }

        if camera.isLowLightBoostSupported {
            camera.automaticallyEnablesLowLightBoostWhenAvailable = true
        }

        camera.isSubjectAreaChangeMonitoringEnabled = true
    }

    private func handleDetected(code: String) {
        guard !code.isEmpty else { return }

        let now = Date()
        if
            lastDeliveredCode == code,
            now.timeIntervalSince(lastDeliveredAt) < dedupCooldown
        {
            return
        }

        lastDeliveredCode = code
        lastDeliveredAt = now
        lastScannedCode = code
        onCodeScanned?(code)
    }
}

// MARK: - Photo Capture Delegate
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate,
    Sendable
{
    private let completion: @Sendable (UIImage?) -> Void

    init(completion: @escaping @Sendable (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            completion(nil)
            return
        }
        completion(image)
    }
}

// MARK: - QR Metadata Delegate
final class QRCodeMetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate
{
    private let onCodeDetected: (String) -> Void

    init(onCodeDetected: @escaping (String) -> Void) {
        self.onCodeDetected = onCodeDetected
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let qrObject = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { $0.type == .qr }),
            let payload = qrObject.stringValue
        else {
            return
        }

        onCodeDetected(payload)
    }
}

// MARK: - Camera Preview Container
final class CameraPreviewContainer: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    var isMirrored = false

    func makeUIView(context: Context) -> CameraPreviewContainer {
        let container = CameraPreviewContainer()
        container.previewLayer.session = session
        container.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        container.previewLayer.connection?.isVideoMirrored = isMirrored
        return container
    }

    func updateUIView(_ uiView: CameraPreviewContainer, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        uiView.previewLayer.connection?.isVideoMirrored = isMirrored
        uiView.setNeedsLayout()
    }
}
