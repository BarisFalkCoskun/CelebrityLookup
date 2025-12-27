import Foundation
import UIKit

// MARK: - API Response Models

struct BoundingBox: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
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

    var uiColor: UIColor {
        UIColor(hex: color) ?? .systemBlue
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

// MARK: - Fast Recognition Response

struct FastRecognitionFace: Codable {
    let boundingBox: BoundingBox

    enum CodingKeys: String, CodingKey {
        case boundingBox = "bounding_box"
    }
}

struct FastRecognitionMatch: Codable, Identifiable {
    var id: String { celebrityId }
    let celebrityId: String
    let name: String
    let confidence: Double
    let color: String
    let faceIndex: Int
    let boundingBox: BoundingBox

    enum CodingKeys: String, CodingKey {
        case celebrityId = "celebrity_id"
        case name, confidence, color
        case faceIndex = "face_index"
        case boundingBox = "bounding_box"
    }

    var uiColor: UIColor {
        UIColor(hex: color) ?? .systemBlue
    }

    /// Convert to CelebrityMatch for use with CutoutPresentationView
    func toCelebrityMatch() -> CelebrityMatch {
        CelebrityMatch(
            id: celebrityId,
            name: name,
            confidence: confidence,
            color: color,
            boundingBox: boundingBox,
            brief: nil
        )
    }
}

struct FastRecognitionResponse: Codable {
    let faces: [FastRecognitionFace]
    let matches: [FastRecognitionMatch]
}

// MARK: - Cutout Response

struct CutoutResponse: Codable {
    let cutoutImage: String  // Base64 PNG with transparency
    let presentationImage: String  // Base64 PNG of B99-style presentation

    enum CodingKeys: String, CodingKey {
        case cutoutImage = "cutout_image"
        case presentationImage = "presentation_image"
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
    case liveCamera
    case cutoutPresentation(UIImage, CelebrityMatch, UIImage)  // presentation, match, originalImage
    case error(String)
}

// MARK: - Detected Face for Live View

struct DetectedFace: Identifiable {
    let id = UUID()
    let bounds: CGRect
    let celebrity: FastRecognitionMatch?

    var color: UIColor {
        celebrity?.uiColor ?? .white
    }

    var name: String? {
        celebrity?.name
    }
}

// MARK: - UIColor Extension

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
