import SwiftUI

struct CelebrityDetailView: View {
    let details: CelebrityDetails
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Professions
                    if !details.profession.isEmpty {
                        professionsSection
                    }

                    // Biography
                    if !details.biography.isEmpty {
                        biographySection
                    }

                    // Filmography
                    if !details.movies.isEmpty {
                        moviesSection
                    }

                    // Discography
                    if !details.music.isEmpty {
                        musicSection
                    }

                    // Awards
                    if !details.awards.isEmpty {
                        awardsSection
                    }
                }
                .padding()
            }
            .navigationTitle(details.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(details.name)
                .font(.largeTitle)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                if let dob = details.dateOfBirth, !dob.isEmpty {
                    Label(formatDate(dob), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let birthplace = details.birthplace, !birthplace.isEmpty {
                    Label(birthplace, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Professions Section

    private var professionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(details.profession, id: \.self) { profession in
                    Text(profession)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(20)
                }
            }
        }
    }

    // MARK: - Biography Section

    private var biographySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Biography", icon: "book.fill")

            Text(details.biography)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }

    // MARK: - Movies Section

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Filmography", icon: "film.fill")

            ForEach(details.movies.prefix(10)) { movie in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title)
                            .font(.headline)

                        Text(movie.role)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(String(movie.year))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                .padding(.vertical, 8)

                if movie.id != details.movies.prefix(10).last?.id {
                    Divider()
                }
            }

            if details.movies.count > 10 {
                Text("+ \(details.movies.count - 10) more")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Music Section

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Discography", icon: "music.note.list")

            ForEach(details.music.prefix(10)) { album in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .font(.headline)

                        Text(album.type.capitalized)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .cornerRadius(4)
                    }

                    Spacer()

                    Text(String(album.year))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)

                if album.id != details.music.prefix(10).last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Awards Section

    private var awardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Awards", icon: "trophy.fill")

            ForEach(details.awards.prefix(10), id: \.self) { award in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)

                    Text(award)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }

            if details.awards.count > 10 {
                Text("+ \(details.awards.count - 10) more awards")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title3)
            .fontWeight(.semibold)
    }

    private func formatDate(_ dateString: String) -> String {
        // Handle YYYY-MM-DD format
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium

        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }
}

#Preview {
    CelebrityDetailView(details: CelebrityDetails(
        id: "sample",
        name: "Sample Celebrity",
        dateOfBirth: "1990-05-15",
        birthplace: "Los Angeles, California",
        profession: ["Actor", "Producer", "Director"],
        biography: "Sample Celebrity is an acclaimed actor known for various roles in blockbuster films and critically acclaimed independent productions. They began their career in theater before transitioning to film and television.",
        movies: [
            MovieCredit(title: "Big Movie", year: 2023, role: "Lead"),
            MovieCredit(title: "Action Film", year: 2021, role: "Supporting"),
            MovieCredit(title: "Drama Series", year: 2019, role: "Lead")
        ],
        music: [
            MusicCredit(title: "Debut Album", year: 2020, type: "album"),
            MusicCredit(title: "Hit Single", year: 2021, type: "single")
        ],
        awards: [
            "Academy Award - Best Actor (2023)",
            "Golden Globe - Best Performance (2022)",
            "Screen Actors Guild Award (2021)"
        ],
        imageUrl: nil
    ))
}
