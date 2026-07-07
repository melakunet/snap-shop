import SwiftUI
import AVFoundation
import PhotosUI
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
    @State private var showFileImporter = false
    #if DEBUG
    @State private var isDebugScanning = false
    @State private var debugTask: Task<Void, Never>?
    #endif

    private var modeColor: Color {
        scanMode == .precision ? Color.Brand.accent : Color.Brand.scanDeep
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)

                modeToggle
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.lg)

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
        }
        .onChange(of: selectedPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        session.publishImage(data)
                    }
                } catch {
                    // TODO: show toast (error variant) when toast plumbing lands
                    print("PhotosPicker loadTransferable failed: \(error)")
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    session.publishImage(data)
                } catch {
                    // TODO: show toast (error variant) when toast plumbing lands
                    print("File importer read failed: \(error)")
                }
            case .failure:
                break
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

    // MARK: — Shutter

    private var shutterArea: some View {
        HStack(spacing: 0) {
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
                        withAnimation(.spring(duration: 0.2)) { isScanning.toggle() }
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

            Button { showFileImporter = true } label: {
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

#Preview {
    CameraView()
}
