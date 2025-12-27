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

                // Face overlay
                FaceOverlayView(
                    faces: detectedFaces,
                    viewSize: geometry.size,
                    imageSize: cameraManager.currentFrameSize
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
                        }
                        Text("Point at a celebrity to identify them")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
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
            cameraManager.onFrameCaptured = { image, faces in
                handleFrameCapture(image: image, visionFaces: faces)
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    private func handleFrameCapture(image: UIImage, visionFaces: [VNFaceObservation]) {
        capturedImage = image
        let imageSize = cameraManager.currentFrameSize

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

    var onFrameCaptured: ((UIImage, [VNFaceObservation]) -> Void)?

    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var lastProcessedTime: Date = .distantPast
    private let processInterval: TimeInterval = 0.1  // 10 fps for face detection

    override init() {
        super.init()
        setupSession()
        setupFaceDetection()
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

    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest?.revision = VNDetectFaceRectanglesRequestRevision3
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

        // Run face detection
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            if let request = faceDetectionRequest {
                try requestHandler.perform([request])

                if let results = request.results as? [VNFaceObservation] {
                    // Convert to UIImage for API
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let context = CIContext()
                    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                        let image = UIImage(cgImage: cgImage)

                        DispatchQueue.main.async {
                            self.onFrameCaptured?(image, results)
                        }
                    }
                }
            }
        } catch {
            print("Face detection error: \(error)")
        }
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

    var body: some View {
        Canvas { context, size in
            for face in faces {
                // Scale face bounds to view size
                let scaledBounds = scaleBounds(face.bounds, from: imageSize, to: size)

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

// MARK: - Color Extension for SwiftUI

extension Color {
    init(_ uiColor: UIColor) {
        self.init(uiColor: uiColor)
    }
}
