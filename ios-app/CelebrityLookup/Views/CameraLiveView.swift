import SwiftUI
import AVFoundation
import Vision
import Combine

struct CameraLiveView: View {
    @Binding var appState: AppState
    @StateObject private var cameraManager = CameraManager()
    @State private var detectedFaces: [DetectedFace] = []
    @State private var lastRecognitionTime: Date = .distantPast
    @State private var isProcessing = false
    @State private var capturedImage: UIImage?
    @State private var serverMatches: [FastRecognitionMatch] = []
    @State private var segmentationMask: CGImage?

    // Detail sheet state
    @State private var selectedCelebrity: FastRecognitionMatch?
    @State private var celebrityDetails: CelebrityDetails?
    @State private var showingDetails = false
    @State private var isLoadingDetails = false

    let recognitionInterval: TimeInterval = 1.0  // Seconds between server calls

    init(appState: Binding<AppState>) {
        self._appState = appState
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview - using custom UIView for reliable sizing
                CameraPreviewRepresentable(session: cameraManager.session)
                    .ignoresSafeArea()

                // Silhouette overlay when we have a segmentation mask and recognized celebrity
                if let mask = segmentationMask,
                   let celebrityFace = detectedFaces.first(where: { $0.celebrity != nil }) {
                    SilhouetteOverlayView(
                        mask: mask,
                        faces: detectedFaces,
                        viewSize: geometry.size,
                        imageSize: cameraManager.currentFrameSize
                    )
                    .id("silhouette-\(celebrityFace.celebrity?.celebrityId ?? "none")")
                    .allowsHitTesting(false)
                }

                // Face overlay for unrecognized faces (rectangles) and name labels
                // Show rectangles when no celebrity silhouette is active
                let hasCelebritySilhouette = segmentationMask != nil && detectedFaces.contains { $0.celebrity != nil }
                FaceOverlayView(
                    faces: detectedFaces,
                    viewSize: geometry.size,
                    imageSize: cameraManager.currentFrameSize,
                    showRectangles: !hasCelebritySilhouette
                )

                // Interactive tap targets for celebrities
                InteractiveFaceOverlay(
                    faces: detectedFaces,
                    viewSize: geometry.size,
                    imageSize: cameraManager.currentFrameSize,
                    onCelebrityTapped: { celebrity in
                        selectCelebrity(celebrity)
                    }
                )

                // Top bar
                VStack {
                    HStack {
                        Button(action: { appState = .idle }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                        .padding()

                        Spacer()

                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Scanning...")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                            .padding()
                        }
                    }

                    Spacer()

                    // Bottom instruction
                    VStack(spacing: 8) {
                        if !serverMatches.isEmpty {
                            Text("\(serverMatches.count) celebrity detected")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Tap on a name to see details")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Text("Point at a celebrity to identify them")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            cameraManager.startSession()
            cameraManager.onFrameCaptured = { image, faces, mask in
                handleFrameCapture(image: image, visionFaces: faces, mask: mask)
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .sheet(isPresented: $showingDetails) {
            celebrityDetailSheet
        }
    }

    // MARK: - Celebrity Detail Sheet

    @ViewBuilder
    private var celebrityDetailSheet: some View {
        if let details = celebrityDetails {
            // CelebrityDetailView has its own NavigationStack
            CelebrityDetailView(details: details)
        } else {
            NavigationStack {
                Group {
                    if isLoadingDetails {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading details...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let celebrity = selectedCelebrity {
                        // Fallback view with basic info
                        ScrollView {
                            VStack(spacing: 24) {
                                // Profile icon
                                ZStack {
                                    Circle()
                                        .fill(Color(celebrity.uiColor).opacity(0.2))
                                        .frame(width: 120, height: 120)
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(Color(celebrity.uiColor))
                                }
                                .padding(.top, 20)

                                // Name
                                Text(celebrity.name)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                // Confidence badge
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                    Text("\(Int(celebrity.confidence * 100))% confidence match")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(20)

                                Divider()
                                    .padding(.horizontal)

                                // Info card
                                VStack(spacing: 12) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 30))
                                        .foregroundColor(.secondary)

                                    Text("Detailed information not available")
                                        .font(.headline)
                                        .foregroundColor(.secondary)

                                    Text("We recognized this celebrity but couldn't fetch their detailed profile from the database.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)

                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle(selectedCelebrity?.name ?? "Celebrity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingDetails = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func selectCelebrity(_ celebrity: FastRecognitionMatch) {
        selectedCelebrity = celebrity
        celebrityDetails = nil
        isLoadingDetails = true
        showingDetails = true

        Task {
            await loadCelebrityDetails(id: celebrity.celebrityId)
        }
    }

    @MainActor
    private func loadCelebrityDetails(id: String) async {
        do {
            let details = try await APIService.shared.getCelebrityDetails(id: id)
            self.celebrityDetails = details
        } catch {
            print("Failed to load celebrity details: \(error)")
            // Keep showing the fallback view with basic info
        }
        isLoadingDetails = false
    }

    private func handleFrameCapture(image: UIImage, visionFaces: [VNFaceObservation], mask: CGImage?) {
        capturedImage = image
        let imageSize = cameraManager.currentFrameSize

        // Update segmentation mask
        DispatchQueue.main.async {
            self.segmentationMask = mask
        }

        // Convert Vision face observations to our DetectedFace model
        var newFaces: [DetectedFace] = []
        for observation in visionFaces {
            // Vision coordinates are normalized (0-1) with origin at bottom-left
            // Convert to image coordinates
            let bounds = CGRect(
                x: observation.boundingBox.origin.x * imageSize.width,
                y: (1 - observation.boundingBox.origin.y - observation.boundingBox.height) * imageSize.height,
                width: observation.boundingBox.width * imageSize.width,
                height: observation.boundingBox.height * imageSize.height
            )

            // Find matching celebrity from server response
            let celebrity = findMatchingCelebrity(for: bounds)
            newFaces.append(DetectedFace(bounds: bounds, celebrity: celebrity))
        }

        DispatchQueue.main.async {
            self.detectedFaces = newFaces
        }

        // Periodically send to server for celebrity recognition
        let now = Date()
        if now.timeIntervalSince(lastRecognitionTime) >= recognitionInterval && !isProcessing && !visionFaces.isEmpty {
            lastRecognitionTime = now
            Task {
                await performServerRecognition(image: image)
            }
        }
    }

    private func findMatchingCelebrity(for bounds: CGRect) -> FastRecognitionMatch? {
        // Find a match from the last server response that overlaps with this face
        for match in serverMatches {
            let matchBounds = match.boundingBox.cgRect
            // Check for significant overlap
            let intersection = bounds.intersection(matchBounds)
            if !intersection.isNull {
                let overlapArea = intersection.width * intersection.height
                let faceArea = bounds.width * bounds.height
                if overlapArea > faceArea * 0.3 {  // 30% overlap threshold
                    return match
                }
            }
        }
        return nil
    }

    @MainActor
    private func performServerRecognition(image: UIImage) async {
        isProcessing = true

        do {
            let response = try await APIService.shared.recognizeFast(image: image)
            self.serverMatches = response.matches

            // Update detected faces with celebrity info
            var updatedFaces: [DetectedFace] = []
            for face in detectedFaces {
                let matchedCelebrity = findMatchingCelebrity(for: face.bounds)
                updatedFaces.append(DetectedFace(bounds: face.bounds, celebrity: matchedCelebrity))
            }
            self.detectedFaces = updatedFaces

        } catch {
            print("Recognition error: \(error)")
        }

        isProcessing = false
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let processingQueue = DispatchQueue(label: "camera.processing", qos: .userInitiated)

    @Published var currentFrameSize: CGSize = CGSize(width: 1280, height: 720)

    // Updated callback to include segmentation mask
    var onFrameCaptured: ((UIImage, [VNFaceObservation], CGImage?) -> Void)?

    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var personSegmentationRequest: VNGeneratePersonSegmentationRequest?
    private var lastProcessedTime: Date = .distantPast
    private let processInterval: TimeInterval = 0.1  // 10 fps for processing

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override init() {
        super.init()
        setupSession()
        setupVisionRequests()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Setup camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Setup video output for processing
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Set video orientation for output
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        session.commitConfiguration()
    }

    private func setupVisionRequests() {
        // Face detection
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest?.revision = VNDetectFaceRectanglesRequestRevision3

        // Person segmentation - using .accurate for best silhouette quality
        personSegmentationRequest = VNGeneratePersonSegmentationRequest()
        personSegmentationRequest?.qualityLevel = .accurate
        personSegmentationRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func startSession() {
        guard !session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processInterval else { return }
        lastProcessedTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Get frame dimensions
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        DispatchQueue.main.async {
            self.currentFrameSize = CGSize(width: width, height: height)
        }

        // Run Vision requests
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        var faceResults: [VNFaceObservation] = []
        var segmentationMask: CGImage?

        do {
            // Build requests array
            var requests: [VNRequest] = []
            if let faceRequest = faceDetectionRequest {
                requests.append(faceRequest)
            }
            if let segRequest = personSegmentationRequest {
                requests.append(segRequest)
            }

            // Perform all requests
            try requestHandler.perform(requests)

            // Get face detection results
            if let faceRequest = faceDetectionRequest,
               let results = faceRequest.results as? [VNFaceObservation] {
                faceResults = results
            }

            // Get person segmentation mask
            if let segRequest = personSegmentationRequest,
               let segResult = segRequest.results?.first as? VNPixelBufferObservation {
                segmentationMask = createCGImage(from: segResult.pixelBuffer)
            }

            // Convert to UIImage for API
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                let image = UIImage(cgImage: cgImage)

                DispatchQueue.main.async {
                    self.onFrameCaptured?(image, faceResults, segmentationMask)
                }
            }

        } catch {
            print("Vision processing error: \(error)")
        }
    }

    private func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Flip vertically to match UIKit coordinate system
        // CIImage has origin at bottom-left, CGImage/UIKit has origin at top-left
        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -ciImage.extent.height))

        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - Camera Preview (UIKit)

class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var session: AVCaptureSession? {
        didSet {
            setupPreviewLayer()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    private func setupPreviewLayer() {
        // Remove existing layer
        previewLayer?.removeFromSuperlayer()

        guard let session = session else { return }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds

        self.layer.addSublayer(layer)
        self.previewLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Critical: Update preview layer frame when view bounds change
        previewLayer?.frame = bounds
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Session is already set, just ensure layout
        uiView.setNeedsLayout()
    }
}

// MARK: - Face Overlay View

struct FaceOverlayView: View {
    let faces: [DetectedFace]
    let viewSize: CGSize
    let imageSize: CGSize
    var showRectangles: Bool = true  // Whether to show rectangle borders

    var body: some View {
        Canvas { context, size in
            for face in faces {
                // Scale face bounds to view size
                let scaledBounds = scaleBounds(face.bounds, from: imageSize, to: size)

                // Only draw rectangles for unrecognized faces, or when silhouette isn't available
                if showRectangles || face.celebrity == nil {
                    // Draw face rectangle
                    let path = RoundedRectangle(cornerRadius: 12)
                        .path(in: scaledBounds.insetBy(dx: -4, dy: -4))

                    // Outer glow
                    context.stroke(
                        path,
                        with: .color(Color(face.color).opacity(0.4)),
                        lineWidth: 12
                    )

                    // Main border
                    context.stroke(
                        path,
                        with: .color(Color(face.color)),
                        lineWidth: 4
                    )
                }

                // Draw name label if celebrity is identified
                if let name = face.name {
                    let labelHeight: CGFloat = 32
                    let labelY = scaledBounds.maxY + 8
                    let labelWidth = min(250, max(scaledBounds.width + 40, 120))
                    let labelX = scaledBounds.midX - labelWidth / 2
                    let labelRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)

                    // Background pill
                    let bgPath = Capsule()
                        .path(in: labelRect)
                    context.fill(bgPath, with: .color(Color(face.color)))

                    // Text
                    context.draw(
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white),
                        at: CGPoint(x: labelRect.midX, y: labelRect.midY),
                        anchor: .center
                    )
                }
            }
        }
    }

    private func scaleBounds(_ bounds: CGRect, from source: CGSize, to target: CGSize) -> CGRect {
        guard source.width > 0 && source.height > 0 else { return .zero }

        // Calculate scale factor to fill target while maintaining aspect ratio
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let scale = max(scaleX, scaleY)

        // Calculate the offset due to aspect fill
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let offsetX = (scaledWidth - target.width) / 2
        let offsetY = (scaledHeight - target.height) / 2

        return CGRect(
            x: bounds.origin.x * scale - offsetX,
            y: bounds.origin.y * scale - offsetY,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }
}

// MARK: - Interactive Face Overlay

struct InteractiveFaceOverlay: View {
    let faces: [DetectedFace]
    let viewSize: CGSize
    let imageSize: CGSize
    let onCelebrityTapped: (FastRecognitionMatch) -> Void

    var body: some View {
        ZStack {
            ForEach(faces) { face in
                if let celebrity = face.celebrity {
                    // Create tappable area for recognized celebrities
                    let scaledBounds = scaleBounds(face.bounds, from: imageSize, to: viewSize)
                    let labelHeight: CGFloat = 32
                    let labelY = scaledBounds.maxY + 8
                    let labelWidth = min(250, max(scaledBounds.width + 40, 120))
                    let labelX = scaledBounds.midX - labelWidth / 2

                    // Invisible tap target over the face box and name label
                    Button(action: {
                        onCelebrityTapped(celebrity)
                    }) {
                        Color.clear
                    }
                    .frame(width: scaledBounds.width + 20, height: scaledBounds.height + labelHeight + 30)
                    .position(
                        x: scaledBounds.midX,
                        y: scaledBounds.midY + labelHeight / 2
                    )
                    .contentShape(Rectangle())

                    // Info button indicator
                    Button(action: {
                        onCelebrityTapped(celebrity)
                    }) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .position(
                        x: scaledBounds.maxX - 5,
                        y: scaledBounds.minY + 5
                    )
                }
            }
        }
    }

    private func scaleBounds(_ bounds: CGRect, from source: CGSize, to target: CGSize) -> CGRect {
        guard source.width > 0 && source.height > 0 else { return .zero }

        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let scale = max(scaleX, scaleY)

        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let offsetX = (scaledWidth - target.width) / 2
        let offsetY = (scaledHeight - target.height) / 2

        return CGRect(
            x: bounds.origin.x * scale - offsetX,
            y: bounds.origin.y * scale - offsetY,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }
}

// MARK: - Silhouette Overlay View

struct SilhouetteOverlayView: View {
    let mask: CGImage
    let faces: [DetectedFace]
    let viewSize: CGSize
    let imageSize: CGSize

    var body: some View {
        // Get the recognized celebrity's face and color
        guard let celebrityFace = faces.first(where: { $0.celebrity != nil }) else {
            return AnyView(EmptyView())
        }

        // Pass the celebrity's face bounds to isolate their silhouette
        return AnyView(
            SilhouetteEdgeRepresentable(
                mask: mask,
                color: celebrityFace.color,
                imageSize: imageSize,
                celebrityBounds: celebrityFace.bounds
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - UIKit-based Silhouette Edge Renderer

struct SilhouetteEdgeRepresentable: UIViewRepresentable {
    let mask: CGImage
    let color: UIColor
    let imageSize: CGSize
    let celebrityBounds: CGRect  // Face bounds in image coordinates

    func makeUIView(context: Context) -> SilhouetteEdgeView {
        let view = SilhouetteEdgeView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(_ uiView: SilhouetteEdgeView, context: Context) {
        uiView.segmentationMask = mask
        uiView.edgeColor = color
        uiView.sourceImageSize = imageSize
        uiView.celebrityBounds = celebrityBounds
        uiView.setNeedsDisplay()
    }
}

class SilhouetteEdgeView: UIView {
    var segmentationMask: CGImage?
    var edgeColor: UIColor = .systemBlue
    var sourceImageSize: CGSize = .zero
    var celebrityBounds: CGRect = .zero

    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Always clear first - critical for when mask is nil or changes
        ctx.clear(rect)

        guard let mask = segmentationMask else {
            // No mask - view stays transparent
            return
        }

        let maskSize = CGSize(width: mask.width, height: mask.height)
        let drawRect = calculateAspectFillRect(maskSize: maskSize, targetSize: rect.size)

        // Always regenerate edge - mask content changes every frame
        if let edge = createCGEdge(from: mask, color: edgeColor) {
            ctx.draw(edge, in: drawRect)
        }
    }

    // Use Core Graphics for edge detection - optimized version
    private func createCGEdge(from mask: CGImage, color: UIColor) -> CGImage? {
        let width = mask.width
        let height = mask.height

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let maskData = context.data else { return nil }
        let pixels = maskData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        guard let outContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        guard let outData = outContext.data else { return nil }
        let outPixels = outData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Initialize output to transparent
        memset(outData, 0, width * height * 4)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rByte = UInt8(r * 255)
        let gByte = UInt8(g * 255)
        let bByte = UInt8(b * 255)

        let edgeRadius = 1  // Thin edge for cleaner look

        // Fast edge detection using only 4 neighbors (up, down, left, right)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = (y * width + x) * 4
                let currentVal = Int(pixels[idx])

                // Skip if current pixel is not part of the mask
                if currentVal < 50 { continue }

                // Check 4-connected neighbors for edge
                let upIdx = ((y - 1) * width + x) * 4
                let downIdx = ((y + 1) * width + x) * 4
                let leftIdx = (y * width + (x - 1)) * 4
                let rightIdx = (y * width + (x + 1)) * 4

                let upVal = Int(pixels[upIdx])
                let downVal = Int(pixels[downIdx])
                let leftVal = Int(pixels[leftIdx])
                let rightVal = Int(pixels[rightIdx])

                // Edge if any neighbor has significantly different value
                let isEdge = (abs(currentVal - upVal) > 50) ||
                             (abs(currentVal - downVal) > 50) ||
                             (abs(currentVal - leftVal) > 50) ||
                             (abs(currentVal - rightVal) > 50)

                if isEdge {
                    // Draw thicker edge by filling a small area
                    for dy in -edgeRadius...edgeRadius {
                        for dx in -edgeRadius...edgeRadius {
                            let py = y + dy
                            let px = x + dx
                            if py >= 0 && py < height && px >= 0 && px < width {
                                let pIdx = (py * width + px) * 4
                                outPixels[pIdx] = rByte
                                outPixels[pIdx + 1] = gByte
                                outPixels[pIdx + 2] = bByte
                                outPixels[pIdx + 3] = 255
                            }
                        }
                    }
                }
            }
        }

        return outContext.makeImage()
    }

    // Simple approach: just colorize the mask outline
    private func createSimpleColoredEdge(from mask: CGImage, color: UIColor) -> CGImage? {
        let ciMask = CIImage(cgImage: mask)
        let extent = ciMask.extent

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        // The mask is grayscale - convert to RGB and detect edges
        // Use Sobel/edge detection via CIEdges
        guard let edges = CIFilter(name: "CIEdges") else {
            print("CIEdges filter not available")
            return nil
        }
        edges.setValue(ciMask, forKey: kCIInputImageKey)
        edges.setValue(5.0, forKey: kCIInputIntensityKey)

        guard let edgeOutput = edges.outputImage else {
            print("Edge detection failed")
            return nil
        }

        // Colorize the edges
        guard let colorMatrix = CIFilter(name: "CIColorMatrix") else {
            print("CIColorMatrix not available")
            return nil
        }
        colorMatrix.setValue(edgeOutput, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        guard let coloredEdges = colorMatrix.outputImage else {
            print("Color matrix failed")
            return nil
        }

        return Self.ciContext.createCGImage(coloredEdges, from: extent)
    }

    // Mask the edge image to only show within the celebrity's region (with soft edges)
    private func maskEdgeToRegion(edge: CGImage) -> CGImage? {
        guard sourceImageSize.width > 0 && sourceImageSize.height > 0 else { return edge }
        guard celebrityBounds.width > 0 && celebrityBounds.height > 0 else { return edge }

        let edgeWidth = CGFloat(edge.width)
        let edgeHeight = CGFloat(edge.height)

        // Scale face bounds from image coordinates to edge image coordinates
        let scaleX = edgeWidth / sourceImageSize.width
        let scaleY = edgeHeight / sourceImageSize.height

        // The segmentation mask was flipped vertically, so flip the Y coordinate
        let flippedFaceY = sourceImageSize.height - celebrityBounds.maxY

        // Expand face bounds to cover the body generously
        let expandedBounds = CGRect(
            x: celebrityBounds.minX - celebrityBounds.width * 2.0,
            y: flippedFaceY - celebrityBounds.height * 0.5,
            width: celebrityBounds.width * 5,
            height: celebrityBounds.height * 6
        )

        // Convert to edge image coordinates
        let edgeRegion = CGRect(
            x: expandedBounds.minX * scaleX,
            y: expandedBounds.minY * scaleY,
            width: expandedBounds.width * scaleX,
            height: expandedBounds.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: edgeWidth, height: edgeHeight))

        guard !edgeRegion.isEmpty else { return edge }

        let ciEdge = CIImage(cgImage: edge)

        // Create a soft radial gradient mask centered on the celebrity
        // This gives a natural falloff instead of hard rectangle edges
        let centerX = edgeRegion.midX
        let centerY = edgeRegion.midY
        let radius = max(edgeRegion.width, edgeRegion.height) * 0.7

        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else { return edge }
        gradientFilter.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        gradientFilter.setValue(radius * 0.6, forKey: "inputRadius0")  // Full opacity radius
        gradientFilter.setValue(radius, forKey: "inputRadius1")        // Fade to transparent radius
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")

        guard let gradient = gradientFilter.outputImage?.cropped(to: ciEdge.extent) else { return edge }

        // Use the gradient as alpha mask for the edge
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return edge }
        blendFilter.setValue(ciEdge, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(gradient, forKey: kCIInputMaskImageKey)

        guard let result = blendFilter.outputImage else { return edge }
        return Self.ciContext.createCGImage(result, from: ciEdge.extent)
    }

    // Fast edge creation using CIEdges filter with transparent background
    private func createFastEdge(from mask: CGImage, color: UIColor) -> CGImage? {
        let ciMask = CIImage(cgImage: mask)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Apply edge detection using CIEdges with higher intensity
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
        edgeFilter.setValue(ciMask, forKey: kCIInputImageKey)
        edgeFilter.setValue(8.0, forKey: kCIInputIntensityKey)  // Increased for thicker edges
        guard let edges = edgeFilter.outputImage else { return nil }

        // Dilate edges to make them thicker
        guard let dilate = CIFilter(name: "CIMorphologyMaximum") else { return nil }
        dilate.setValue(edges, forKey: kCIInputImageKey)
        dilate.setValue(3.0, forKey: kCIInputRadiusKey)  // Thicken the edge
        guard let thickEdges = dilate.outputImage else { return nil }

        // Create a solid color image
        guard let colorGenerator = CIFilter(name: "CIConstantColorGenerator") else { return nil }
        colorGenerator.setValue(CIColor(red: r, green: g, blue: b, alpha: 1.0), forKey: kCIInputColorKey)
        guard let solidColor = colorGenerator.outputImage?.cropped(to: ciMask.extent) else { return nil }

        // Convert edges to grayscale for alpha mask
        guard let grayscale = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        grayscale.setValue(thickEdges, forKey: kCIInputImageKey)
        guard let grayEdges = grayscale.outputImage else { return nil }

        // Blend solid color with transparent background using edges as mask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
        blendFilter.setValue(solidColor, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(grayEdges, forKey: kCIInputMaskImageKey)
        guard let result = blendFilter.outputImage else { return nil }

        return Self.ciContext.createCGImage(result, from: ciMask.extent)
    }

    // Morphological edge detection: dilate - original = outer edge
    private func createMorphologicalEdge(from mask: CGImage, color: UIColor) -> CGImage? {
        let ciMask = CIImage(cgImage: mask)
        let extent = ciMask.extent

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Dilate the mask to expand it
        guard let dilate = CIFilter(name: "CIMorphologyMaximum") else { return nil }
        dilate.setValue(ciMask, forKey: kCIInputImageKey)
        dilate.setValue(6.0, forKey: kCIInputRadiusKey)  // Edge thickness

        guard let dilated = dilate.outputImage?.cropped(to: extent) else { return nil }

        // Subtract original from dilated to get outer edge only
        guard let subtract = CIFilter(name: "CISubtractBlendMode") else { return nil }
        subtract.setValue(dilated, forKey: kCIInputImageKey)
        subtract.setValue(ciMask, forKey: kCIInputBackgroundImageKey)

        guard let edgeMask = subtract.outputImage?.cropped(to: extent) else { return nil }

        // Create solid color
        guard let colorGen = CIFilter(name: "CIConstantColorGenerator") else { return nil }
        colorGen.setValue(CIColor(red: r, green: g, blue: b, alpha: 1.0), forKey: kCIInputColorKey)

        guard let solidColor = colorGen.outputImage?.cropped(to: extent) else { return nil }

        // Use edge mask as alpha for the color
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(solidColor, forKey: kCIInputImageKey)
        blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blend.setValue(edgeMask, forKey: kCIInputMaskImageKey)

        guard let result = blend.outputImage else { return nil }

        return Self.ciContext.createCGImage(result, from: extent)
    }

    private func calculateAspectFillRect(maskSize: CGSize, targetSize: CGSize) -> CGRect {
        let scaleX = targetSize.width / maskSize.width
        let scaleY = targetSize.height / maskSize.height
        let scale = max(scaleX, scaleY)

        let scaledWidth = maskSize.width * scale
        let scaledHeight = maskSize.height * scale
        let offsetX = (scaledWidth - targetSize.width) / 2
        let offsetY = (scaledHeight - targetSize.height) / 2

        return CGRect(
            x: -offsetX,
            y: -offsetY,
            width: scaledWidth,
            height: scaledHeight
        )
    }

}

// MARK: - Color Extension for SwiftUI

extension Color {
    init(_ uiColor: UIColor) {
        self.init(uiColor: uiColor)
    }
}
