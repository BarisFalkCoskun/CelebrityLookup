import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// On-device cutout generator using Apple's Vision framework
/// Uses the Neural Engine for instant, high-quality person segmentation
class CutoutGenerator {
    static let shared = CutoutGenerator()

    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    private init() {}

    /// Generate a B99-style cutout presentation from an image
    /// - Parameters:
    ///   - image: The source image containing the person
    ///   - faceBox: The bounding box of the face to isolate (in image coordinates)
    ///   - color: The accent color for the presentation
    ///   - name: The celebrity's name
    /// - Returns: A tuple containing (cutoutImage, presentationImage)
    func generateCutout(
        from image: UIImage,
        faceBox: BoundingBox,
        color: UIColor,
        name: String
    ) async throws -> (cutout: UIImage, presentation: UIImage) {

        guard let cgImage = image.cgImage else {
            throw CutoutError.invalidImage
        }

        // 1. Perform person segmentation using Vision
        let mask = try await performSegmentation(on: cgImage)

        // 2. Create cutout image (person with transparent background)
        let cutout = try createCutoutImage(from: cgImage, mask: mask, faceBox: faceBox)

        // 3. Create B99-style presentation
        let presentation = createPresentation(cutout: cutout, color: color, name: name)

        return (cutout, presentation)
    }

    // MARK: - Private Methods

    private func performSegmentation(on image: CGImage) async throws -> CVPixelBuffer {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = request.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(throwing: CutoutError.segmentationFailed)
                    return
                }

                continuation.resume(returning: result.pixelBuffer)
            }

            // Use best quality for cutout (not real-time, so we can afford it)
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func createCutoutImage(
        from image: CGImage,
        mask: CVPixelBuffer,
        faceBox: BoundingBox
    ) throws -> UIImage {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        // Convert mask to CGImage
        var ciMask = CIImage(cvPixelBuffer: mask)

        // Scale mask to match image dimensions
        let maskWidth = CGFloat(CVPixelBufferGetWidth(mask))
        let maskHeight = CGFloat(CVPixelBufferGetHeight(mask))

        let scaleX = imageWidth / maskWidth
        let scaleY = imageHeight / maskHeight
        ciMask = ciMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // The mask from Vision has Y origin at bottom, flip it
        ciMask = ciMask.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -imageHeight))

        // Isolate the target person using face location
        ciMask = isolateTargetPerson(mask: ciMask, faceBox: faceBox, imageSize: CGSize(width: imageWidth, height: imageHeight))

        // Apply mask to original image
        let ciImage = CIImage(cgImage: image)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw CutoutError.filterCreationFailed
        }

        blendFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(ciMask, forKey: kCIInputMaskImageKey)

        guard let output = blendFilter.outputImage,
              let cgOutput = ciContext.createCGImage(output, from: ciImage.extent) else {
            throw CutoutError.renderFailed
        }

        return UIImage(cgImage: cgOutput)
    }

    private func isolateTargetPerson(
        mask: CIImage,
        faceBox: BoundingBox,
        imageSize: CGSize
    ) -> CIImage {
        // Create a soft radial gradient centered on the face to isolate the target person
        let faceCenterX = CGFloat(faceBox.x + faceBox.width / 2)
        let faceCenterY = CGFloat(faceBox.y + faceBox.height / 2)

        // Calculate radius that covers the person's body (generous estimate based on face size)
        let faceSize = max(CGFloat(faceBox.width), CGFloat(faceBox.height))
        let personRadius = faceSize * 4.0  // Body is roughly 4x the face size

        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else {
            return mask
        }

        gradientFilter.setValue(CIVector(x: faceCenterX, y: imageSize.height - faceCenterY), forKey: "inputCenter")
        gradientFilter.setValue(personRadius * 0.8, forKey: "inputRadius0")  // Full opacity
        gradientFilter.setValue(personRadius * 1.2, forKey: "inputRadius1")  // Fade out
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")

        guard let gradient = gradientFilter.outputImage?.cropped(to: mask.extent) else {
            return mask
        }

        // Multiply mask with gradient to isolate target person
        guard let multiplyFilter = CIFilter(name: "CIMultiplyBlendMode") else {
            return mask
        }

        multiplyFilter.setValue(mask, forKey: kCIInputImageKey)
        multiplyFilter.setValue(gradient, forKey: kCIInputBackgroundImageKey)

        return multiplyFilter.outputImage ?? mask
    }

    private func createPresentation(cutout: UIImage, color: UIColor, name: String) -> UIImage {
        // Create B99-style presentation with gradient background
        let presentationSize = CGSize(width: 1080, height: 1350)  // Portrait aspect ratio

        let renderer = UIGraphicsImageRenderer(size: presentationSize)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: presentationSize)
            let ctx = context.cgContext

            // 1. Draw gradient background
            drawGradientBackground(in: ctx, rect: rect, color: color)

            // 2. Draw the cutout with glow effect
            drawCutoutWithGlow(cutout: cutout, in: ctx, rect: rect, color: color)

            // 3. Draw name label at bottom
            drawNameLabel(name: name, in: ctx, rect: rect, color: color)
        }
    }

    private func drawGradientBackground(in ctx: CGContext, rect: CGRect, color: UIColor) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let darkColor = UIColor(hue: hue, saturation: min(saturation * 1.2, 1.0), brightness: brightness * 0.3, alpha: 1.0)
        let lightColor = UIColor(hue: hue, saturation: saturation * 0.8, brightness: min(brightness * 1.2, 1.0), alpha: 0.8)

        let colors = [darkColor.cgColor, lightColor.cgColor]
        let locations: [CGFloat] = [0.0, 1.0]

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: locations) else { return }

        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: rect.width, y: rect.height),
            options: []
        )
    }

    private func drawCutoutWithGlow(cutout: UIImage, in ctx: CGContext, rect: CGRect, color: UIColor) {
        guard let cgImage = cutout.cgImage else { return }

        // Calculate the drawing rect (centered, with padding)
        let padding: CGFloat = 60
        let maxWidth = rect.width - padding * 2
        let maxHeight = rect.height - padding * 2 - 150  // Leave room for name

        let imageAspect = cutout.size.width / cutout.size.height
        let maxAspect = maxWidth / maxHeight

        var drawWidth: CGFloat
        var drawHeight: CGFloat

        if imageAspect > maxAspect {
            drawWidth = maxWidth
            drawHeight = maxWidth / imageAspect
        } else {
            drawHeight = maxHeight
            drawWidth = maxHeight * imageAspect
        }

        let drawX = (rect.width - drawWidth) / 2
        let drawY = (rect.height - 150 - drawHeight) / 2  // Offset up for name

        let drawRect = CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)

        // Draw glow (multiple shadows with different sizes)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 40, color: color.withAlphaComponent(0.8).cgColor)
        ctx.draw(cgImage, in: drawRect)
        ctx.restoreGState()

        // Draw second glow layer
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 20, color: color.cgColor)
        ctx.draw(cgImage, in: drawRect)
        ctx.restoreGState()

        // Draw the actual cutout
        ctx.draw(cgImage, in: drawRect)
    }

    private func drawNameLabel(name: String, in ctx: CGContext, rect: CGRect, color: UIColor) {
        let nameText = name.uppercased()

        // Create attributed string for the name
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 56, weight: .black),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]

        let attributedString = NSAttributedString(string: nameText, attributes: attributes)

        // Calculate position (bottom center)
        let textSize = attributedString.size()
        let textRect = CGRect(
            x: (rect.width - textSize.width) / 2,
            y: rect.height - 120,
            width: textSize.width,
            height: textSize.height
        )

        // Draw name glow
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 15, color: color.cgColor)
        attributedString.draw(in: textRect)
        ctx.restoreGState()

        // Draw name
        attributedString.draw(in: textRect)
    }
}

// MARK: - Errors

enum CutoutError: Error, LocalizedError {
    case invalidImage
    case segmentationFailed
    case filterCreationFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid source image"
        case .segmentationFailed:
            return "Person segmentation failed"
        case .filterCreationFailed:
            return "Failed to create image filter"
        case .renderFailed:
            return "Failed to render output image"
        }
    }
}
