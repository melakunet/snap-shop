import AVKit
import SwiftUI
import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum ScanMode {
    case precision
    case deep
}

struct CameraView: View {
    @StateObject private var session = CameraSession()
    @State private var scanMode: ScanMode = .precision
    @State private var isScanning = false
    @State private var flashOn = false
    @State private var deepPulse = false
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showVideoImporter = false
    @State private var showResults = false
    @State private var searchQuery = ""
    @State private var submittedQuery = ""
    @FocusState private var searchFocused: Bool
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var showTranscriptSheet = false
    @State private var voiceHint = ""
    @State private var pastedURL: URL?
    @State private var showClipboardAlert = false
    @State private var prefillQuery = ""
    @State private var showCropSheet = false
    @State private var pendingUploadData: Data? = nil
    @State private var transcriptVideoPlayer: AVPlayer? = nil
    @State private var frameFromVideo: Data? = nil
    @State private var showVideoFrameCrop = false
    #if DEBUG
    @State private var isDebugScanning = false
    @State private var debugTask: Task<Void, Never>?
    #endif

    private var modeColor: Color {
        scanMode == .precision ? Color.Brand.accent : Color.Brand.scanDeep
    }

    var body: some View {
        mainStack
            .sheet(isPresented: $showTranscriptSheet) { transcriptSheet }
            .onChange(of: transcriber.partialTranscript) { _, partial in handlePartialTranscript(partial) }
            .onChange(of: transcriber.phase) { _, phase in handlePhaseChange(phase) }
            .onChange(of: showTranscriptSheet) { _, showing in
                if showing, let url = session.capturedVideoURL {
                    transcriptVideoPlayer = AVPlayer(url: url)
                    transcriptVideoPlayer?.play()
                } else {
                    transcriptVideoPlayer?.pause()
                    transcriptVideoPlayer = nil
                }
            }
            .fullScreenCover(isPresented: $showVideoFrameCrop, onDismiss: {
                if !showResults { frameFromVideo = nil }
            }) {
                if let data = frameFromVideo {
                    CropSheet(
                        imageData: data,
                        onConfirm: { uploadData in
                            pendingUploadData = uploadData
                            showVideoFrameCrop = false
                            showResults = true
                        },
                        onCancel: {
                            showVideoFrameCrop = false
                            frameFromVideo = nil
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $showCropSheet, onDismiss: {
                // Swipe-to-dismiss is disabled (fullScreenCover), but if dismissed via Cancel
                // the handler already clears capturedImageData. This is a safety net.
                if !showResults { session.capturedImageData = nil }
            }) {
                if let data = session.capturedImageData {
                    CropSheet(
                        imageData: data,
                        onConfirm: { uploadData in
                            pendingUploadData = uploadData
                            showCropSheet = false
                            showResults = true
                        },
                        onCancel: {
                            showCropSheet = false
                            session.capturedImageData = nil
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $showResults) {
                if let frameData = frameFromVideo {
                    ResultsView(scanMode: .precision, imageData: frameData, uploadData: pendingUploadData)
                } else if let videoURL = session.capturedVideoURL {
                    ResultsView(scanMode: .deep, videoURL: videoURL, hint: voiceHint)
                } else if let data = session.capturedImageData {
                    ResultsView(scanMode: scanMode, imageData: data, uploadData: pendingUploadData)
                } else if !submittedQuery.isEmpty {
                    ResultsView(textQuery: submittedQuery)
                } else if let url = pastedURL {
                    ResultsView(productPageURL: url, prefillQuery: $prefillQuery)
                }
            }
            .alert("No URL found", isPresented: $showClipboardAlert) {
                Button("OK") {}
            } message: {
                Text("Copy a product link and try again.")
            }
    }

    private var mainStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)

                modeToggle
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.lg)

                searchBar
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.sm)

                if !searchFocused && searchQuery.isEmpty {
                    pasteChip
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.top, Spacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()
                viewfinderContainer
                Spacer()

                hintLabel
                    .padding(.bottom, Spacing.lg)

                shutterArea
                    .padding(.bottom, Spacing.xxxl)
            }
            #if DEBUG
            debugScanOverlay
            #endif
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: scanMode) { _, _ in
            withAnimation(.spring(duration: 0.2)) { isScanning = false }
            searchFocused = false
        }
        .onChange(of: selectedPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        session.publishImage(data)
                    }
                } catch {
                    print("PhotosPicker loadTransferable failed: \(error)")
                }
            }
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let video = try await newItem.loadTransferable(type: VideoTransferable.self) {
                        session.publishVideo(video.url)
                    }
                } catch {
                    print("PhotosPicker video load failed: \(error)")
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) { session.publishImage(data) }
            case .failure:
                break
            }
        }
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        ) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                if (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil {
                    session.publishVideo(tempURL)
                }
            case .failure:
                break
            }
        }
        .onChange(of: session.capturedImageData) { _, newData in
            if newData != nil { showCropSheet = true }
        }
        .onChange(of: session.capturedVideoURL) { _, url in
            guard let url else { return }
            Task { await transcriber.transcribeVideoAudio(url: url) }
            showTranscriptSheet = true
        }
        .onChange(of: session.isRecording) { _, recording in
            withAnimation(.spring(duration: 0.2)) { isScanning = recording }
        }
        .onChange(of: showResults) { _, isShowing in
            if !isShowing {
                session.capturedImageData = nil
                session.capturedVideoURL = nil
                submittedQuery = ""
                voiceHint = ""
                pastedURL = nil
                pendingUploadData = nil
                frameFromVideo = nil
                if !prefillQuery.isEmpty {
                    searchQuery = prefillQuery
                    prefillQuery = ""
                    searchFocused = true
                }
            }
        }
    }

    // MARK: — Top bar

    private var topBar: some View {
        HStack {
            circleButton("xmark") {}
            Spacer()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
            flashToggleButton
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private var flashToggleButton: some View {
        Button { flashOn.toggle() } label: {
            Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(flashOn ? Color.Brand.accent : .white.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
    }

    // MARK: — Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton("Precision", icon: "camera.aperture", mode: .precision)
            modeButton("Deep", icon: "video.fill", mode: .deep)
        }
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func modeButton(_ label: String, icon: String, mode: ScanMode) -> some View {
        let active = scanMode == mode
        return Button {
            withAnimation(.spring(duration: 0.25)) { scanMode = mode }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(Typography.callout.weight(active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Color.Brand.accentOn : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(active ? modeColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
    }

    // MARK: — Viewfinder

    private var viewfinderContainer: some View {
        ZStack {
            if session.permissionGranted {
                CameraPreviewView(session: session.session)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else if session.permissionDenied {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 280, height: 280)
                    .overlay(
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "camera.slash")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Camera access required.")
                                .font(Typography.callout)
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(Typography.callout.weight(.semibold))
                            .foregroundStyle(Color.Brand.accent)
                        }
                        .padding(Spacing.lg)
                    )
            } else {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 280, height: 280)
            }

            if scanMode == .precision {
                precisionOverlay
            } else {
                deepOverlay
            }
        }
        .animation(.easeInOut(duration: 0.22), value: scanMode)
    }

    private var precisionOverlay: some View {
        ZStack {
            CornerBrackets()
                .stroke(
                    Color.Brand.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 280, height: 280)

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(Color.Brand.accent.opacity(0.8))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var deepOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg + 4)
                .strokeBorder(Color.Brand.scanDeep.opacity(0.4), lineWidth: 2)
                .frame(width: 280, height: 280)
                .scaleEffect(deepPulse ? 1.05 : 0.98)
                .opacity(deepPulse ? 0.0 : 1.0)
                .animation(
                    .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                    value: deepPulse
                )

            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.Brand.scanDeep, lineWidth: 1.5)
                .frame(width: 280, height: 280)

            VStack(spacing: Spacing.sm) {
                Image(systemName: "video.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.Brand.scanDeep)
                Text("Deep Scan")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.Brand.scanDeep)
                    .tracking(1)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .onAppear { deepPulse = true }
        .onDisappear { deepPulse = false }
    }

    // MARK: — Hint

    private var hintLabel: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: scanMode == .precision ? "scope" : "arrow.left.and.right")
                .font(.system(size: 11))
            Text(
                scanMode == .precision
                    ? "Hold steady — one precise shot"
                    : "Pan slowly — capturing all angles"
            )
            .font(Typography.caption)
        }
        .foregroundStyle(.white.opacity(0.65))
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: scanMode)
    }

    // MARK: — Search

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
            TextField("Search by product name…", text: $searchQuery)
                .font(Typography.callout)
                .foregroundStyle(.white)
                .tint(Color.Brand.accent)
                .focused($searchFocused)
                .onSubmit { submitTextSearch() }
                .submitLabel(.search)
            searchBarTrailingButton
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(searchFocused ? 0.14 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .animation(.spring(duration: 0.2), value: searchFocused)
        .animation(.spring(duration: 0.2), value: searchQuery.isEmpty)
        .animation(.spring(duration: 0.2), value: isListening)
    }

    private func submitTextSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchFocused = false
        submittedQuery = trimmed
        showResults = true
    }

    // MARK: — Shutter

    private var shutterArea: some View {
        HStack(spacing: 0) {
            if scanMode == .precision {
                PhotosPicker(
                    selection: $selectedPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            } else {
                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }

            Spacer()

            ZStack {
                if scanMode == .deep && isScanning {
                    Circle()
                        .strokeBorder(Color.Brand.scanDeep.opacity(0.4), lineWidth: 2)
                        .frame(width: 92, height: 92)
                        .scaleEffect(isScanning ? 1.15 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                            value: isScanning
                        )
                }

                Button {
                    if scanMode == .precision {
                        session.capturePhoto(flashOn: flashOn)
                    } else {
                        if session.isRecording {
                            session.stopRecording()
                        } else {
                            session.startRecording()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isScanning && scanMode == .deep ? Color.Brand.error : modeColor)
                            .frame(width: 72, height: 72)

                        if scanMode == .deep && isScanning {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: scanMode == .precision ? "camera.fill" : "video.fill")
                                .foregroundStyle(Color.Brand.accentOn)
                                .font(.system(size: 26, weight: .medium))
                        }
                    }
                }
                .disabled(scanMode == .precision && session.isCapturing)
                .scaleEffect(isScanning || session.isCapturing ? 0.88 : 1.0)
                .animation(.spring(duration: 0.2), value: isScanning)
                .animation(.spring(duration: 0.2), value: session.isCapturing)
            }

            Spacer()

            Button {
                if scanMode == .precision {
                    showFileImporter = true
                } else {
                    showVideoImporter = true
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: — Paste link

    private var pasteChip: some View {
        Button(action: handlePasteLink) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                Text("Paste link")
                    .font(Typography.caption.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handlePasteLink() {
        guard let raw = UIPasteboard.general.string,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" || url.scheme == "http"
        else {
            showClipboardAlert = true
            return
        }
        pastedURL = url
        showResults = true
    }

    // MARK: — Voice hint

    private func handlePartialTranscript(_ partial: String) {
        if !showTranscriptSheet { searchQuery = partial } else { voiceHint = partial }
    }

    private func handlePhaseChange(_ phase: SpeechTranscriber.Phase) {
        guard case .done(let text) = phase else { return }
        if showTranscriptSheet { voiceHint = text } else { searchQuery = text; transcriber.reset() }
    }

    private var isListening: Bool {
        switch transcriber.phase {
        case .listening: return true
        default: return false
        }
    }

    private var isTranscribing: Bool {
        switch transcriber.phase {
        case .processingFile: return true
        default: return false
        }
    }

    @ViewBuilder
    private var searchBarTrailingButton: some View {
        if isListening {
            Button { transcriber.stopListening() } label: {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.Brand.accent)
            }
            .transition(.opacity)
        } else if searchFocused || !searchQuery.isEmpty {
            Button("Search") { submitTextSearch() }
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(
                    searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.Brand.accent.opacity(0.4)
                        : Color.Brand.accent
                )
                .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            Button { transcriber.startListening() } label: {
                Image(systemName: "mic")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var transcriptSheet: some View {
        NavigationStack {
            ZStack {
                Color.Brand.background.ignoresSafeArea()
                if isTranscribing {
                    VStack(spacing: Spacing.lg) {
                        ProgressView()
                            .tint(Color.Brand.accent)
                        Text("Transcribing audio…")
                            .font(Typography.body)
                            .foregroundStyle(Color.Brand.textSecondary)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            if let player = transcriptVideoPlayer {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    VideoPlayer(player: player)
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                    Button {
                                        let time = player.currentTime()
                                        player.pause()
                                        showTranscriptSheet = false
                                        Task { await extractFrameAndCrop(at: time) }
                                    } label: {
                                        Label("Scan this frame", systemImage: "camera.viewfinder")
                                            .font(Typography.callout.weight(.semibold))
                                            .foregroundStyle(Color.Brand.accentOn)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Spacing.sm)
                                            .background(Color.Brand.accent)
                                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                    }
                                }
                                .padding(.horizontal, Spacing.xl)
                                HStack {
                                    VStack { Divider() }
                                    Text("or add a hint for whole-video scan")
                                        .font(Typography.caption)
                                        .foregroundStyle(Color.Brand.textSecondary)
                                        .fixedSize()
                                    VStack { Divider() }
                                }
                                .padding(.horizontal, Spacing.xl)
                            }
                            Text("Add a hint (optional)")
                                .font(Typography.headline)
                                .foregroundStyle(Color.Brand.textPrimary)
                                .padding(.horizontal, Spacing.xl)
                            TextEditor(text: $voiceHint)
                                .font(Typography.body)
                                .foregroundStyle(Color.Brand.textPrimary)
                                .frame(minHeight: 120)
                                .padding(Spacing.md)
                                .background(Color.Brand.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .padding(.horizontal, Spacing.xl)
                            Text("Edit or add a description to help identify the product.")
                                .font(Typography.caption)
                                .foregroundStyle(Color.Brand.textSecondary)
                                .padding(.horizontal, Spacing.xl)
                        }
                        .padding(.top, Spacing.xl)
                        .padding(.bottom, Spacing.xl)
                    }
                }
            }
            .navigationTitle("Voice Hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") {
                        voiceHint = ""
                        showTranscriptSheet = false
                        showResults = true
                    }
                    .foregroundStyle(Color.Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start Scan") {
                        showTranscriptSheet = false
                        showResults = true
                    }
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.accent)
                    .disabled(isTranscribing)
                }
            }
        }
    }

    // MARK: — Frame extraction

    private func extractFrameAndCrop(at time: CMTime) async {
        guard let url = session.capturedVideoURL else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        guard let (cgImage, _) = try? await generator.image(at: time) else { return }
        frameFromVideo = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
        showVideoFrameCrop = true
    }

    // MARK: — Debug (compiled out in Release builds)

    #if DEBUG
    private var debugScanOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    guard let data = session.capturedImageData else {
                        print("[DEBUG] No image — capture or pick one first")
                        return
                    }
                    debugTask?.cancel()
                    debugTask = Task {
                        isDebugScanning = true
                        do {
                            let (product, prices) = try await BackendClient.scan(imageData: data)
                            print("[DEBUG] ✅ \(product.brand) \(product.model) (\(product.category))")
                            print("[DEBUG] 🔍 Query: \(product.searchQuery)")
                            print("[DEBUG] 📊 Confidence: \(String(format: "%.2f", product.confidence))")
                            prices.forEach {
                                print("[DEBUG] 💰 \($0.source): \($0.price) · \($0.delivery)")
                            }
                        } catch {
                            print("[DEBUG] ❌ scan() error: \(error)")
                        }
                        isDebugScanning = false
                    }
                } label: {
                    Text(isDebugScanning ? "Scanning…" : "⚡ Scan API")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.7))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.yellow.opacity(0.5), lineWidth: 1))
                }
                .disabled(isDebugScanning || session.capturedImageData == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            Spacer()
        }
    }
    #endif
}

// MARK: — Corner-bracket Shape (Precision mode)

private struct CornerBrackets: Shape {
    var bracketLength: CGFloat = 26
    private let cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var pathResult = Path()
        let length = bracketLength
        let curve = cornerRadius

        // Top-left
        pathResult.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        pathResult.addLine(to: CGPoint(x: rect.minX, y: rect.minY + curve))
        pathResult.addQuadCurve(
            to: CGPoint(x: rect.minX + curve, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        pathResult.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        // Top-right
        pathResult.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        pathResult.addLine(to: CGPoint(x: rect.maxX - curve, y: rect.minY))
        pathResult.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + curve),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        pathResult.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        // Bottom-right
        pathResult.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        pathResult.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - curve))
        pathResult.addQuadCurve(
            to: CGPoint(x: rect.maxX - curve, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        pathResult.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        // Bottom-left
        pathResult.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        pathResult.addLine(to: CGPoint(x: rect.minX + curve, y: rect.maxY))
        pathResult.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - curve),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        pathResult.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return pathResult
    }
}

// MARK: — Video Transferable (PhotosPicker Deep mode)

private struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

#Preview {
    CameraView()
}
