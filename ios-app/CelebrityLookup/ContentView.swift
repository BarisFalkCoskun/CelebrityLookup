import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var appState: AppState = .idle
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?

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
                        selectedPhotoItem: $selectedPhotoItem
                    )

                case .capturing:
                    ProgressView("Preparing...")
                        .scaleEffect(1.5)

                case .processing:
                    ProcessingView()

                case .results(let response):
                    ResultView(response: response) {
                        appState = .idle
                        selectedImage = nil
                    }

                case .error(let message):
                    ErrorView(message: message) {
                        appState = .idle
                    }
                }
            }
            .navigationTitle("Celebrity Lookup")
            .navigationBarTitleDisplayMode(.inline)
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

    private func processImage(_ image: UIImage) async {
        appState = .processing

        do {
            let response = try await APIService.shared.recognizeCelebrities(image: image)
            appState = .results(response)
        } catch {
            appState = .error(error.localizedDescription)
        }
    }
}

// MARK: - Idle View

struct IdleView: View {
    @Binding var showingCamera: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App icon/illustration
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("Identify Celebrities")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Take a photo or choose from your library to identify celebrities and learn more about them.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                Button(action: { showingCamera = true }) {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

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

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
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

                Text("Detecting and identifying celebrities...")
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
