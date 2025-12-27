import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var appState: AppState = .idle
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isGeneratingCutout = false
    @State private var cutoutCelebrity: CelebrityMatch?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                switch appState {
                case .idle:
                    IdleView(
                        showingCamera: $showingCamera,
                        selectedPhotoItem: $selectedPhotoItem,
                        onLiveModeSelected: {
                            appState = .liveCamera
                        }
                    )

                case .capturing:
                    ProgressView("Preparing...")
                        .scaleEffect(1.5)

                case .processing:
                    ProcessingView()

                case .results(let response):
                    ResultView(
                        response: response,
                        originalImage: selectedImage,
                        onReset: {
                            appState = .idle
                            selectedImage = nil
                        },
                        onCelebrityTapped: { celebrity in
                            generateCutout(for: celebrity, from: response)
                        }
                    )

                case .liveCamera:
                    CameraLiveView(appState: $appState)
                        .ignoresSafeArea()

                case .cutoutPresentation(let presentationImage, let celebrity, let originalImage):
                    CutoutPresentationView(
                        presentationImage: presentationImage,
                        celebrity: celebrity,
                        originalImage: originalImage,
                        onDismiss: {
                            appState = .idle
                            selectedImage = nil
                        },
                        onShowDetails: {
                            // Navigate to details
                        }
                    )

                case .error(let message):
                    ErrorView(message: message) {
                        appState = .idle
                    }
                }

                // Loading overlay for cutout generation
                if isGeneratingCutout, let celebrity = cutoutCelebrity {
                    CutoutLoadingView(celebrityName: celebrity.name, color: celebrity.uiColor)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(shouldHideNavBar)
            .sheet(isPresented: $showingCamera) {
                CameraView(image: $selectedImage)
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let newValue {
                        appState = .capturing
                        if let data = try? await newValue.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            selectedImage = image
                            await processImage(image)
                        } else {
                            appState = .error("Could not load selected image")
                        }
                    }
                }
            }
            .onChange(of: selectedImage) { _, newValue in
                if let image = newValue, case .idle = appState {
                    Task {
                        await processImage(image)
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch appState {
        case .liveCamera, .cutoutPresentation:
            return ""
        default:
            return "Celebrity Lookup"
        }
    }

    private var shouldHideNavBar: Bool {
        switch appState {
        case .liveCamera, .cutoutPresentation:
            return true
        default:
            return false
        }
    }

    private func processImage(_ image: UIImage) async {
        appState = .processing

        do {
            let response = try await APIService.shared.recognizeCelebrities(image: image)
            appState = .results(response)
        } catch {
            appState = .error(error.localizedDescription)
        }
    }

    private func generateCutout(for celebrity: CelebrityMatch, from response: RecognitionResponse) {
        guard let image = selectedImage else { return }

        isGeneratingCutout = true
        cutoutCelebrity = celebrity

        Task {
            do {
                let cutoutResponse = try await APIService.shared.generateCutout(
                    image: image,
                    faceBox: celebrity.boundingBox,
                    color: celebrity.color,
                    name: celebrity.name
                )

                // Decode presentation image
                if let imageData = Data(base64Encoded: cutoutResponse.presentationImage),
                   let presentationImage = UIImage(data: imageData) {
                    await MainActor.run {
                        isGeneratingCutout = false
                        cutoutCelebrity = nil
                        appState = .cutoutPresentation(presentationImage, celebrity, image)
                    }
                } else {
                    throw APIError.invalidImage
                }
            } catch {
                await MainActor.run {
                    isGeneratingCutout = false
                    cutoutCelebrity = nil
                    appState = .error("Failed to generate cutout: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Idle View

struct IdleView: View {
    @Binding var showingCamera: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    var onLiveModeSelected: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App icon/illustration
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 140, height: 140)

                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue.gradient)
            }

            VStack(spacing: 12) {
                Text("Identify Celebrities")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Take a photo or use live mode to identify celebrities and learn more about them.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                // Live Mode - Primary action
                Button(action: onLiveModeSelected) {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Live Mode")
                        Spacer()
                        Text("Real-time")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }

                // Take Photo
                Button(action: { showingCamera = true }) {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(14)
                }

                // Choose from Library
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Pulsing background
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                            pulseScale = 1.2
                        }
                    }

                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }

            VStack(spacing: 8) {
                Text("Analyzing Image")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Detecting faces and identifying celebrities...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Something Went Wrong")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Try Again", action: onRetry)
                .font(.headline)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
}

#Preview {
    ContentView()
}
