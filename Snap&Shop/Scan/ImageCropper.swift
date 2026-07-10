import CoreGraphics
import ImageIO
import Vision

/// Prepares captured images for backend upload using only thread-safe CoreGraphics APIs:
/// attention-saliency crop → 1024 px longest-edge downscale → JPEG quality-step to < 100 KB.
enum ImageCropper {

    static let uploadMaxBytes = 100_000
    private static let uploadMaxDimension = 1024
    private static let qualitySteps: [Double] = [0.8, 0.65, 0.5, 0.35, 0.2, 0.1]

    // MARK: — Public API

    /// Full Precision pipeline: saliency crop → downscale → compress.
    /// Runs on a detached task; never blocks the calling actor.
    /// Returns `data` unchanged when it cannot be decoded as an image.
    static func prepareForUpload(data: Data) async -> Data {
        #if DEBUG
        let before = data.count
        #endif

        let result = await Task.detached(priority: .userInitiated) { () -> Data in
            guard let cgImage = decodeCGImage(from: data) else { return data }
            let cropped = saliencyCrop(cgImage) ?? centerCrop(cgImage)
            let scaled  = downscale(cropped, maxDimension: uploadMaxDimension)
            return compress(scaled, maxBytes: uploadMaxBytes)
        }.value

        #if DEBUG
        let pct = before > 0 ? result.count * 100 / before : 0
        print("[ImageCropper] \(before / 1_024) KB → \(result.count / 1_024) KB (\(pct)% of original)")
        #endif
        return result
    }

    /// Re-compress a JPEG only when it exceeds `maxBytes`; otherwise return it unchanged.
    /// Safe to call from any thread or actor (uses CoreGraphics only).
    static func cap(jpeg: Data, maxBytes: Int = uploadMaxBytes) -> Data {
        guard jpeg.count > maxBytes,
              let cgImage = decodeCGImage(from: jpeg) else { return jpeg }
        return compress(cgImage, maxBytes: maxBytes)
    }

    /// Step JPEG quality from 0.8 → 0.1 and return the first encoding that fits within `maxBytes`.
    /// Falls back to quality 0.1 if no step satisfies the cap.
    static func compress(_ cgImage: CGImage, maxBytes: Int) -> Data {
        for quality in qualitySteps {
            if let data = jpegData(from: cgImage, quality: quality), data.count <= maxBytes {
                return data
            }
        }
        return jpegData(from: cgImage, quality: 0.1) ?? Data()
    }

    // MARK: — Manual crop (CropSheet API)

    /// Returns the attention-saliency suggested crop rect in normalized coordinates
    /// (top-left origin, 0–1 range). Falls back to center-80 % when Vision finds nothing.
    static func saliencyRect(for data: Data) async -> CGRect {
        await Task.detached(priority: .userInitiated) { () -> CGRect in
            guard let cgImage = decodeCGImage(from: data) else {
                return CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            }
            return saliencyNormalizedRect(for: cgImage)
                ?? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        }.value
    }

    /// Crop the image to a caller-supplied normalized rect, then downscale + compress.
    static func prepareForUpload(data: Data, cropRect: CGRect) async -> Data {
        #if DEBUG
        let before = data.count
        #endif

        let result = await Task.detached(priority: .userInitiated) { () -> Data in
            guard let cgImage = decodeCGImage(from: data) else { return data }
            let pw = CGFloat(cgImage.width), ph = CGFloat(cgImage.height)
            let pixelRect = CGRect(
                x: cropRect.minX * pw, y: cropRect.minY * ph,
                width: cropRect.width * pw, height: cropRect.height * ph
            ).intersection(CGRect(x: 0, y: 0, width: pw, height: ph))

            let toCrop: CGImage
            if pixelRect.width >= 32, pixelRect.height >= 32,
               let c = cgImage.cropping(to: pixelRect) {
                toCrop = c
            } else {
                toCrop = cgImage
            }
            let scaled = downscale(toCrop, maxDimension: uploadMaxDimension)
            return compress(scaled, maxBytes: uploadMaxBytes)
        }.value

        #if DEBUG
        let pct = before > 0 ? result.count * 100 / before : 0
        print("[ImageCropper] manual crop: \(before / 1_024) KB → \(result.count / 1_024) KB (\(pct)% of original)")
        #endif
        return result
    }

    // MARK: — Private

    private static func decodeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Attention-saliency crop with 20 % padding. Returns nil when no salient region is found.
    private static func saliencyCrop(_ cgImage: CGImage) -> CGImage? {
        guard let norm = saliencyNormalizedRect(for: cgImage) else { return nil }
        let pw = CGFloat(cgImage.width), ph = CGFloat(cgImage.height)
        let pixelRect = CGRect(x: norm.minX * pw, y: norm.minY * ph,
                               width: norm.width * pw, height: norm.height * ph)
        guard pixelRect.width >= 32, pixelRect.height >= 32 else { return nil }
        return cgImage.cropping(to: pixelRect)
    }

    /// Normalized saliency bounding rect (top-left origin). Shared by saliencyCrop and saliencyRect.
    private static func saliencyNormalizedRect(for cgImage: CGImage) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        guard
            let obs = request.results?.first as? VNSaliencyImageObservation,
            let objects = obs.salientObjects, !objects.isEmpty
        else { return nil }

        // Union all salient bounding boxes (Vision: bottom-left origin, y increases up)
        let union = objects.reduce(CGRect.null) { $0.union($1.boundingBox) }

        // Flip to top-left origin, add 20 % padding, clamp to unit square
        let flipped = CGRect(x: union.minX, y: 1 - union.maxY,
                             width: union.width, height: union.height)
        return flipped
            .insetBy(dx: -flipped.width * 0.2, dy: -flipped.height * 0.2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Center-80 % crop used as fallback when saliency returns no region.
    private static func centerCrop(_ cgImage: CGImage) -> CGImage {
        let pw = CGFloat(cgImage.width), ph = CGFloat(cgImage.height)
        let w = pw * 0.8, h = ph * 0.8
        let rect = CGRect(x: (pw - w) / 2, y: (ph - h) / 2, width: w, height: h)
        return cgImage.cropping(to: rect) ?? cgImage
    }

    /// Downscale so the longest pixel edge ≤ `maxDimension`. No-op if already within bounds.
    private static func downscale(_ cgImage: CGImage, maxDimension: Int) -> CGImage {
        let pw = cgImage.width, ph = cgImage.height
        guard max(pw, ph) > maxDimension else { return cgImage }
        let scale = Double(maxDimension) / Double(max(pw, ph))
        let newW = Int((Double(pw) * scale).rounded())
        let newH = Int((Double(ph) * scale).rounded())
        let space = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? cgImage
    }

    private static func jpegData(from cgImage: CGImage, quality: Double) -> Data? {
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buf, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buf as Data
    }
}
