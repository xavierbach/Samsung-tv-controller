import UIKit
import Vision

/// A photo prepared for a Frame TV: the 16:9 preview shown in the sheet and
/// the JPEG bytes that get uploaded.
struct ArtworkImage: Identifiable {
    let id = UUID()
    let preview: UIImage
    let jpeg: Data
    // Set when the server already archived this image (generated art):
    // hanging then references the library instead of re-uploading.
    var libraryId: String? = nil
}

/// Crops any photo to the Frame TV's 16:9 canvas. A naive center crop
/// decapitates portraits and slices subjects standing off-center, so the crop
/// window is placed with Vision's attention-based saliency: it slides along
/// the long axis until whatever the photo is actually *of* — faces, pets, the
/// subject — sits inside the frame.
enum SmartCropper {
    private static let targetAspect: CGFloat = 16.0 / 9.0
    private static let frameResolution = CGSize(width: 3840, height: 2160)

    static func artwork(from image: UIImage) -> ArtworkImage? {
        let cropped = crop16x9(image)
        let sized = downscale(cropped, toFit: frameResolution)
        guard let jpeg = sized.jpegData(compressionQuality: 0.9) else { return nil }
        return ArtworkImage(preview: sized, jpeg: jpeg)
    }

    // MARK: crop

    static func crop16x9(_ image: UIImage) -> UIImage {
        let upright = normalizeOrientation(image)
        guard let cg = upright.cgImage else { return upright }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        var cropW = w
        var cropH = h
        if w / h > targetAspect {
            cropW = (h * targetAspect).rounded(.down)
        } else {
            cropH = (w / targetAspect).rounded(.down)
        }
        if cropW >= w - 1 && cropH >= h - 1 { return upright }  // already 16:9

        // Vision reports normalized rects with a bottom-left origin; convert
        // to pixel coordinates with the top-left origin CGImage cropping uses.
        let focus = salientRect(in: cg).map { r in
            CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h)
        } ?? CGRect(x: w / 2, y: h / 2, width: 0, height: 0)

        let crop = CGRect(
            x: placeWindow(length: cropW, within: w, coveringMin: focus.minX,
                           max: focus.maxX, mid: focus.midX),
            y: placeWindow(length: cropH, within: h, coveringMin: focus.minY,
                           max: focus.maxY, mid: focus.midY),
            width: cropW, height: cropH
        )
        guard let croppedCG = cg.cropping(to: crop) else { return upright }
        return UIImage(cgImage: croppedCG)
    }

    /// Place a crop window of `length` inside [0, within], centered on the
    /// salient region but shifted as needed so the whole region stays inside
    /// (when it fits — a region bigger than the window just stays centered).
    private static func placeWindow(
        length: CGFloat, within: CGFloat,
        coveringMin lo: CGFloat, max hi: CGFloat, mid: CGFloat
    ) -> CGFloat {
        var origin = mid - length / 2
        if hi - lo <= length {
            origin = min(max(origin, hi - length), lo)
        }
        return min(max(origin, 0), within - length)
    }

    private static func salientRect(in cg: CGImage) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let boxes = request.results?.first?.salientObjects,
              let first = boxes.first
        else { return nil }
        return boxes.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    // MARK: raster helpers

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.cgImage != nil { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func downscale(_ image: UIImage, toFit target: CGSize) -> UIImage {
        let size = image.size
        guard size.width > target.width || size.height > target.height else { return image }
        let scale = min(target.width / size.width, target.height / size.height)
        let out = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: out))
        }
    }
}
