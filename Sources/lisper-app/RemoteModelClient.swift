import Foundation
import LisperCore

enum RemoteModelClient {
    static func transcribe(samples: [Float], configuration: ModelSlotConfiguration) async throws -> String {
        let body: [String: Any] = [
            "sampleRate": WhisperRuntimeDefaults.sampleRate,
            "samples": samples.map(Double.init)
        ]
        let data = try await post(body: body, configuration: configuration)
        return parseText(from: data) ?? ""
    }

    static func cleanup(text: String, configuration: ModelSlotConfiguration) async throws -> String {
        let data = try await post(body: ["text": text], configuration: configuration)
        return parseText(from: data) ?? ""
    }

    static func parseText(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(RemoteTextResponse.self, from: data) {
            return decoded.text ?? decoded.transcript ?? decoded.output
        }

        let plainText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plainText?.isEmpty == false ? plainText : nil
    }

    private static func post(body: [String: Any], configuration: ModelSlotConfiguration) async throws -> Data {
        let endpoint = configuration.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            throw RemoteModelError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let reference = configuration.apiKeyReference,
           let token = AppKeychain.load(reference: reference),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteModelError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteModelError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}

private struct RemoteTextResponse: Decodable {
    var text: String?
    var transcript: String?
    var output: String?
}

enum RemoteModelError: Error, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid remote endpoint"
        case .invalidResponse:
            return "Remote endpoint returned an invalid response"
        case .httpStatus(let status):
            return "Remote endpoint returned HTTP \(status)"
        }
    }
}
