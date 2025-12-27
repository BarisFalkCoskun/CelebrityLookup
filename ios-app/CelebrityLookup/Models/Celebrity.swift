import Foundation

// MARK: - API Response Models

struct BoundingBox: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct CelebrityMatch: Codable, Identifiable {
    let id: String
    let name: String
    let confidence: Double
    let color: String
    let boundingBox: BoundingBox
    let brief: String?

    enum CodingKeys: String, CodingKey {
        case id, name, confidence, color, brief
        case boundingBox = "bounding_box"
    }
}

struct RecognitionResponse: Codable {
    let annotatedImage: String  // Base64 encoded PNG
    let celebrities: [CelebrityMatch]

    enum CodingKeys: String, CodingKey {
        case annotatedImage = "annotated_image"
        case celebrities
    }
}

// MARK: - Celebrity Details

struct MovieCredit: Codable, Identifiable {
    var id: String { "\(title)-\(year)" }
    let title: String
    let year: Int
    let role: String
}

struct MusicCredit: Codable, Identifiable {
    var id: String { "\(title)-\(year)" }
    let title: String
    let year: Int
    let type: String  // album, single, etc.
}

struct CelebrityDetails: Codable, Identifiable {
    let id: String
    let name: String
    let dateOfBirth: String?
    let birthplace: String?
    let profession: [String]
    let biography: String
    let movies: [MovieCredit]
    let music: [MusicCredit]
    let awards: [String]
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, birthplace, profession, biography, movies, music, awards
        case dateOfBirth = "date_of_birth"
        case imageUrl = "image_url"
    }
}

// MARK: - App State

enum AppState {
    case idle
    case capturing
    case processing
    case results(RecognitionResponse)
    case error(String)
}
