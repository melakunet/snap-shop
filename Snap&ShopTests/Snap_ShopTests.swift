import Testing
import CoreGraphics
import ImageIO
@testable import Snap_Shop

struct ImageCropperTests {

    // MARK: — Helpers

    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Two-colour blocks so the JPEG isn't trivially tiny (avoids single-DC-coefficient edge cases)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return ctx.makeImage()!
    }

    private func jpegData(_ cgImage: CGImage, quality: Double = 0.95) -> Data {
        let buf = NSMutableData()
        let dest = CGImageDestinationCreateWithData(buf, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return buf as Data
    }

    // MARK: — compress

    @Test func compressReturnsDataUnderNormalCap() throws {
        let cgImage = makeCGImage(width: 2048, height: 2048)
        let result = ImageCropper.compress(cgImage, maxBytes: ImageCropper.uploadMaxBytes)
        #expect(result.count <= ImageCropper.uploadMaxBytes)
        #expect(!result.isEmpty)
    }

    @Test func compressExhaustsAllStepsWhenCapIsZero() throws {
        // maxBytes = 0 → every quality step produces count > 0, so all fail;
        // the function must still return the quality-0.1 fallback (non-empty).
        let cgImage = makeCGImage(width: 64, height: 64)
        let result = ImageCropper.compress(cgImage, maxBytes: 0)
        let floor = jpegData(cgImage, quality: 0.1)
        #expect(!result.isEmpty)
        // The fallback JPEG and the helper-produced one are from the same encoder + input,
        // so they should be byte-for-byte equal.
        #expect(result == floor)
    }

    @Test func compressResultNeverExceedsLowestQuality() throws {
        // A very tight cap (1 KB) forces all steps to fail; result ≤ quality-0.1 output size.
        let cgImage = makeCGImage(width: 512, height: 512)
        let result = ImageCropper.compress(cgImage, maxBytes: 1_000)
        let floor = jpegData(cgImage, quality: 0.1)
        #expect(!result.isEmpty)
        #expect(result.count <= floor.count)
    }

    // MARK: — cap

    @Test func capPassesThroughSmallData() throws {
        let jpeg = jpegData(makeCGImage(width: 64, height: 64), quality: 0.5)
        #expect(jpeg.count < ImageCropper.uploadMaxBytes)
        #expect(ImageCropper.cap(jpeg: jpeg).count == jpeg.count)
    }

    @Test func capCompressesDataOverLimit() throws {
        let cgImage = makeCGImage(width: 2048, height: 2048)
        let large = jpegData(cgImage, quality: 0.99)
        guard large.count > ImageCropper.uploadMaxBytes else { return }
        #expect(ImageCropper.cap(jpeg: large).count <= ImageCropper.uploadMaxBytes)
    }

    // MARK: — prepareForUpload

    @Test func prepareForUploadProducesDataUnderCap() async throws {
        // 2048×2048 so the downscale step (longest edge → 1024 px) actually fires
        let jpeg = jpegData(makeCGImage(width: 2048, height: 2048), quality: 0.95)
        let result = await ImageCropper.prepareForUpload(data: jpeg)
        #expect(result.count <= ImageCropper.uploadMaxBytes)
        #expect(!result.isEmpty)
    }

    @Test func prepareForUploadReturnsInputForNonImageData() async throws {
        let garbage = Data([0x00, 0x01, 0x02])
        #expect(await ImageCropper.prepareForUpload(data: garbage) == garbage)
    }
}
