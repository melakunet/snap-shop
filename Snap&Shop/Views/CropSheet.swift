import SwiftUI

/// Full-screen crop editor shown after a precision image is captured/imported.
/// Defaults the crop rect to the attention-saliency suggestion from ImageCropper,
/// animating in once Vision finishes (~100–300 ms). The user drags corners or the
/// body to adjust. Confirming compresses the cropped region and calls onConfirm.
struct CropSheet: View {

    let imageData: Data
    let onConfirm: (Data) -> Void
    let onCancel: () -> Void

    // MARK: — State

    @State private var cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var saliencyReady = false
    @State private var isCompressing = false
    @State private var uiImage: UIImage? = nil
    @State private var dragStart: CGRect? = nil     // start rect for active drag gesture

    private let handleSize: CGFloat = 24
    private let minFraction: CGFloat = 0.05         // minimum crop dimension (normalized)

    // MARK: — Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let frame = displayFrame(in: geo.size)
                let vc    = viewCropRect(in: frame)

                ZStack {
                    Color.black.ignoresSafeArea()

                    // Full image
                    if let img = uiImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }

                    // Dim outside crop rect (even-odd fill punches hole)
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geo.size))
                        p.addRect(vc)
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    // Rule-of-thirds grid inside crop rect
                    gridLines(vc: vc)

                    // Crop border
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: vc.width, height: vc.height)
                        .position(x: vc.midX, y: vc.midY)
                        .allowsHitTesting(false)

                    // Body drag area (transparent, fills interior)
                    Color.white.opacity(0.001)
                        .frame(
                            width: max(1, vc.width  - handleSize),
                            height: max(1, vc.height - handleSize)
                        )
                        .position(x: vc.midX, y: vc.midY)
                        .gesture(bodyGesture(frame: frame))

                    // Corner handles (rendered after body drag, so get touch priority)
                    cornerHandle(.topLeft,     at: CGPoint(x: vc.minX, y: vc.minY), frame: frame)
                    cornerHandle(.topRight,    at: CGPoint(x: vc.maxX, y: vc.minY), frame: frame)
                    cornerHandle(.bottomLeft,  at: CGPoint(x: vc.minX, y: vc.maxY), frame: frame)
                    cornerHandle(.bottomRight, at: CGPoint(x: vc.maxX, y: vc.maxY), frame: frame)

                    // Saliency computing indicator
                    if !saliencyReady {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            uiImage = UIImage(data: imageData)
        }
        .task {
            let rect = await ImageCropper.saliencyRect(for: imageData)
            withAnimation(.spring(duration: 0.45)) { cropRect = rect }
            saliencyReady = true
        }
    }

    // MARK: — Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel", action: onCancel)
                .foregroundStyle(.white)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isCompressing {
                ProgressView().tint(Color.Brand.accent)
            } else {
                Button("Scan") { confirmCrop() }
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.accent)
            }
        }
    }

    // MARK: — Layout helpers

    /// Pixel frame of the displayed image inside the GeometryReader's coordinate space.
    private func displayFrame(in containerSize: CGSize) -> CGRect {
        guard let img = uiImage,
              img.size.width > 0, img.size.height > 0,
              containerSize.width > 0, containerSize.height > 0
        else { return CGRect(origin: .zero, size: containerSize) }

        let ia = img.size.width / img.size.height
        let ca = containerSize.width / containerSize.height
        let size: CGSize = ia > ca
            ? CGSize(width: containerSize.width, height: containerSize.width / ia)
            : CGSize(width: containerSize.height * ia, height: containerSize.height)
        return CGRect(
            x: (containerSize.width  - size.width)  / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    /// Maps the normalized cropRect into the image's display frame.
    private func viewCropRect(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + cropRect.minX * frame.width,
            y: frame.minY + cropRect.minY * frame.height,
            width: cropRect.width  * frame.width,
            height: cropRect.height * frame.height
        )
    }

    // MARK: — Rule-of-thirds grid

    private func gridLines(vc: CGRect) -> some View {
        let tw = vc.width  / 3
        let th = vc.height / 3
        return Path { p in
            for i in 1...2 {
                let x = vc.minX + tw * CGFloat(i)
                p.move(to: CGPoint(x: x, y: vc.minY))
                p.addLine(to: CGPoint(x: x, y: vc.maxY))
                let y = vc.minY + th * CGFloat(i)
                p.move(to: CGPoint(x: vc.minX, y: y))
                p.addLine(to: CGPoint(x: vc.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    // MARK: — Corner handles

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func cornerHandle(_ corner: Corner, at point: CGPoint, frame: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .position(point)
            .gesture(cornerGesture(corner, frame: frame))
    }

    // MARK: — Gestures

    private func bodyGesture(frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { drag in
                if dragStart == nil { dragStart = cropRect }
                guard let start = dragStart else { return }
                let dx = drag.translation.width  / frame.width
                let dy = drag.translation.height / frame.height
                cropRect = CGRect(
                    x: (start.minX + dx).clamped(to: 0...(1 - start.width)),
                    y: (start.minY + dy).clamped(to: 0...(1 - start.height)),
                    width: start.width, height: start.height
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: Corner, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart == nil { dragStart = cropRect }
                guard let start = dragStart else { return }
                let dx = drag.translation.width  / frame.width
                let dy = drag.translation.height / frame.height
                cropRect = adjustedRect(start: start, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func adjustedRect(start: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var x0 = start.minX, y0 = start.minY
        var x1 = start.maxX, y1 = start.maxY
        switch corner {
        case .topLeft:
            x0 = (x0 + dx).clamped(to: 0...(x1 - minFraction))
            y0 = (y0 + dy).clamped(to: 0...(y1 - minFraction))
        case .topRight:
            x1 = (x1 + dx).clamped(to: (x0 + minFraction)...1)
            y0 = (y0 + dy).clamped(to: 0...(y1 - minFraction))
        case .bottomLeft:
            x0 = (x0 + dx).clamped(to: 0...(x1 - minFraction))
            y1 = (y1 + dy).clamped(to: (y0 + minFraction)...1)
        case .bottomRight:
            x1 = (x1 + dx).clamped(to: (x0 + minFraction)...1)
            y1 = (y1 + dy).clamped(to: (y0 + minFraction)...1)
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: — Confirm

    private func confirmCrop() {
        isCompressing = true
        Task {
            let data = await ImageCropper.prepareForUpload(data: imageData, cropRect: cropRect)
            isCompressing = false
            onConfirm(data)
        }
    }
}
