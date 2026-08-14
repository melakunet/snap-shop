import AVFoundation
import Combine

final class CameraSession: NSObject, ObservableObject {
    @Published var permissionGranted = false
    @Published var permissionDenied = false
    @Published var capturedImageData: Data?
    @Published var capturedVideoURL: URL?
    @Published var isCapturing = false
    @Published var isRecording = false
    @Published var detectedBarcode: String? = nil

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "com.snapshop.camera", qos: .userInitiated)

    override init() {
        super.init()
        checkPermission()
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            sessionQueue.async { self.configureSession() }
        case .denied, .restricted:
            permissionDenied = true
        case .notDetermined:
            Task { await self.requestPermission() }
        @unknown default:
            Task { await self.requestPermission() }
        }
    }

    func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permissionGranted = granted
        permissionDenied = !granted
        if granted {
            sessionQueue.async { self.configureSession() }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        // .high (1080p) supports both AVCapturePhotoOutput and AVCaptureMovieFileOutput.
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
            movieFileOutput.maxRecordedDuration = CMTime(seconds: 10, preferredTimescale: 600)
        }
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            // Must be set AFTER adding to session so availableMetadataObjectTypes is populated
            let supported = metadataOutput.availableMetadataObjectTypes
            let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .qr]
            metadataOutput.metadataObjectTypes = wanted.filter { supported.contains($0) }
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        }
        session.commitConfiguration()
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            if self.movieFileOutput.isRecording { self.movieFileOutput.stopRecording() }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: — Precision capture

    func capturePhoto(flashOn: Bool) {
        guard !isCapturing else { return }
        isCapturing = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = flashOn ? .on : .off
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func publishImage(_ data: Data) {
        DispatchQueue.main.async { self.capturedImageData = data }
    }

    func clearDetectedBarcode() {
        detectedBarcode = nil
    }

    // MARK: — Deep capture

    func startRecording() {
        guard !isRecording,
              let connection = movieFileOutput.connection(with: .video) else { return }
        // Stabilise if the device supports it
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        DispatchQueue.main.async { self.isRecording = true }
        sessionQueue.async { self.movieFileOutput.startRecording(to: url, recordingDelegate: self) }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { self.movieFileOutput.stopRecording() }
    }

    func publishVideo(_ url: URL) {
        DispatchQueue.main.async { self.capturedVideoURL = url }
    }
}

// MARK: — Still photo delegate

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error _: Error?
    ) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            self.isCapturing = false
            self.capturedImageData = data
        }
    }
}

// MARK: — Barcode delegate

extension CameraSession: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else { return }
        DispatchQueue.main.async {
            if self.detectedBarcode != value {
                self.detectedBarcode = value
            }
        }
    }
}

// MARK: — Movie file delegate

extension CameraSession: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
            if error == nil {
                self.capturedVideoURL = outputFileURL
            }
        }
    }
}
