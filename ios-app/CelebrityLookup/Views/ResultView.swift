import SwiftUI

struct ResultView: View {
    let response: RecognitionResponse
    let onDismiss: () -> Void

    @State private var selectedCelebrity: CelebrityMatch?
    @State private var celebrityDetails: CelebrityDetails?
    @State private var showingDetail = false
    @State private var isLoadingDetails = false

    var annotatedImage: UIImage? {
        guard let data = Data(base64Encoded: response.annotatedImage) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                Spacer()
                Text("\(response.celebrities.count) found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()

            // Annotated image
            if let image = annotatedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .padding(.horizontal)
            }

            // Celebrity chips
            if response.celebrities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No celebrities recognized")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap to learn more")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(response.celebrities) { celebrity in
                                CelebrityChip(
                                    celebrity: celebrity,
                                    isSelected: selectedCelebrity?.id == celebrity.id
                                )
                                .onTapGesture {
                                    selectedCelebrity = celebrity
                                    loadDetails(for: celebrity)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
            }

            Spacer()
        }
        .sheet(isPresented: $showingDetail) {
            if let details = celebrityDetails {
                CelebrityDetailView(details: details)
            } else if isLoadingDetails {
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func loadDetails(for celebrity: CelebrityMatch) {
        isLoadingDetails = true
        showingDetail = true

        Task {
            do {
                celebrityDetails = try await APIService.shared.getCelebrityDetails(id: celebrity.id)
            } catch {
                // Create basic details from match info
                celebrityDetails = CelebrityDetails(
                    id: celebrity.id,
                    name: celebrity.name,
                    dateOfBirth: nil,
                    birthplace: nil,
                    profession: celebrity.brief?.components(separatedBy: ", ") ?? [],
                    biography: "Details not available in database.",
                    movies: [],
                    music: [],
                    awards: [],
                    imageUrl: nil
                )
            }
            isLoadingDetails = false
        }
    }
}

// MARK: - Celebrity Chip

struct CelebrityChip: View {
    let celebrity: CelebrityMatch
    let isSelected: Bool

    var chipColor: Color {
        Color(hex: celebrity.color) ?? .blue
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(celebrity.name)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text("\(Int(celebrity.confidence * 100))%")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.85))

            if let brief = celebrity.brief {
                Text(brief)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(chipColor)
                .shadow(color: chipColor.opacity(0.5), radius: isSelected ? 8 : 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
