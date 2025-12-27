import SwiftUI

struct CutoutPresentationView: View {
    let presentationImage: UIImage
    let celebrity: CelebrityMatch
    let originalImage: UIImage
    let onDismiss: () -> Void
    let onShowDetails: () -> Void

    @State private var showImage = false
    @State private var showName = false
    @State private var showButtons = false
    @State private var imageScale: CGFloat = 0.8
    @State private var nameOffset: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - gradient based on celebrity color
                LinearGradient(
                    colors: [
                        Color(celebrity.uiColor).opacity(0.2),
                        Color(celebrity.uiColor).opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Close button
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(radius: 4)
                        }
                        .padding()

                        Spacer()
                    }

                    Spacer()

                    // Cutout presentation image
                    Image(uiImage: presentationImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width * 0.9)
                        .scaleEffect(showImage ? 1.0 : imageScale)
                        .opacity(showImage ? 1.0 : 0.0)
                        .shadow(color: Color(celebrity.uiColor).opacity(0.5), radius: 20)

                    Spacer()

                    // Name and buttons
                    VStack(spacing: 24) {
                        // Celebrity name - B99 style
                        Text(celebrity.name.uppercased())
                            .font(.system(size: 36, weight: .black, design: .default))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 2, y: 2)
                            .shadow(color: Color(celebrity.uiColor), radius: 10)
                            .offset(y: showName ? 0 : nameOffset)
                            .opacity(showName ? 1.0 : 0.0)

                        // Confidence badge
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("\(Int(celebrity.confidence * 100))% Match")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .opacity(showName ? 1.0 : 0.0)

                        // Action buttons
                        VStack(spacing: 12) {
                            Button(action: onShowDetails) {
                                HStack {
                                    Image(systemName: "person.text.rectangle")
                                    Text("View Details")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(Color(celebrity.uiColor))
                                .cornerRadius(14)
                            }

                            Button(action: {
                                // Share functionality
                                shareImage()
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 40)
                        .opacity(showButtons ? 1.0 : 0.0)
                        .offset(y: showButtons ? 0 : 30)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            animateIn()
        }
    }

    private func animateIn() {
        // Staggered animation for dramatic effect
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showImage = true
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
            showName = true
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5)) {
            showButtons = true
        }
    }

    private func shareImage() {
        let activityVC = UIActivityViewController(
            activityItems: [presentationImage],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Tap-able Celebrity Card for Results View

struct CelebrityResultCard: View {
    let celebrity: CelebrityMatch
    let originalImage: UIImage
    let onTap: () -> Void
    @State private var isLoading = false
    @State private var presentationImage: UIImage?

    var body: some View {
        Button(action: {
            onTap()
        }) {
            HStack(spacing: 16) {
                // Color indicator
                Circle()
                    .fill(Color(celebrity.uiColor))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(celebrity.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let brief = celebrity.brief {
                        Text(brief)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Confidence
                Text("\(Int(celebrity.confidence * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(celebrity.uiColor))

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color(celebrity.uiColor).opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Loading Overlay for Cutout Generation

struct CutoutLoadingView: View {
    let celebrityName: String
    let color: UIColor

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color(color).opacity(0.3), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color(color), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }

                VStack(spacing: 8) {
                    Text("Creating Cutout")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(celebrityName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(color))
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
}

#Preview {
    CutoutPresentationView(
        presentationImage: UIImage(systemName: "person.fill")!,
        celebrity: CelebrityMatch(
            id: "test",
            name: "Test Celebrity",
            confidence: 0.85,
            color: "#FF6B6B",
            boundingBox: BoundingBox(x: 0, y: 0, width: 100, height: 100),
            brief: "Actor, Producer"
        ),
        originalImage: UIImage(systemName: "person.fill")!,
        onDismiss: {},
        onShowDetails: {}
    )
}
