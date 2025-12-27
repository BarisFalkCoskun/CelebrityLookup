import Foundation
import UIKit

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidImage
    case invalidURL
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case notFound
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the image"
        case .invalidURL:
            return "Invalid server URL"
        case .serverError(let code):
            return "Server error (code: \(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        case .notFound:
            return "Celebrity not found"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - API Service

class APIService {
    static let shared = APIService()

    // Configure this for your backend
    // For simulator: http://localhost:8000
    // For real device: http://<your-mac-ip>:8000
    private var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://localhost:8000"
        #else
        return "http://192.168.1.234:8000"  // Your Mac's IP address
        #endif
    }

    private init() {}

    // MARK: - Recognize Celebrities

    func recognizeCelebrities(image: UIImage) async throws -> RecognitionResponse {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.invalidImage
        }

        guard let url = URL(string: "\(baseURL)/recognize") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60  // ML processing can take time

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.unknown
            }

            guard httpResponse.statusCode == 200 else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(RecognitionResponse.self, from: data)

        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Get Celebrity Details

    func getCelebrityDetails(id: String) async throws -> CelebrityDetails {
        guard let url = URL(string: "\(baseURL)/celebrity/\(id)") else {
            throw APIError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.unknown
            }

            if httpResponse.statusCode == 404 {
                throw APIError.notFound
            }

            guard httpResponse.statusCode == 200 else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(CelebrityDetails.self, from: data)

        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Health Check

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
